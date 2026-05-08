# Stage 4.03 — Keywords Audit (findings)

**Generated:** 2026-05-06
**Universe input:** `.llm/audit_2026_launch/universe/keywords.json` (1,420 distinct keywords; 15,539 datasheet × keyword assignments; 45 keywords flagged `is_faction_keyword=true` in Wahapedia)
**Code root scanned:** `40k/autoloads/`, `40k/phases/`, `40k/scripts/` (excluded `40k/.claude/worktrees/` per scope, excluded `40k/tests*/`)
**Live-validation harness:** `addons/godot_mcp` bridge against the running editor (Fight Phase, Round 1, both rosters loaded) — see Section 4.

---

## 1. Rules-bearing keyword classification

Schema: `Keyword | Datasheets | Depth | Correctness | Evidence (file:line) | Notes`

### 1.1 Universal type keywords (the must-be-rule-bearing set per Wahapedia)

| Keyword | Datasheets | Depth | Correctness | Evidence | Notes |
|---|---:|---|---|---|---|
| CHARACTER | 682 | **L** | ✅ | `40k/autoloads/CharacterAttachmentManager.gd:26-27,70,136,147` (attachment gating); `40k/autoloads/ArmyListManager.gd:1289` (enhancement bearer must be CHARACTER); `40k/autoloads/MissionManager.gd:720` (Sites of Power character-claim VP); `40k/autoloads/UnitAbilityManager.gd:3095`, `40k/autoloads/StratagemManager.gd:1478`, `40k/autoloads/SecondaryMissionManager.gd:884,1207`. Live: `RulesEngine.is_monster_or_vehicle(U_GHAZGHKULL_THRAKA_A)` returns `true`; `U_SHIELD_CAPTAIN_A.meta.keywords` contains `"CHARACTER"`. | Gating works for character-claim VP, attachment, enhancement validation. Look-Out-Sir 9e wounds-threshold removed correctly (commit 8749eb4); `is_character_protected_from_targeting` no longer exists at runtime (live: `RulesEngine.has_method("is_character_protected_from_targeting") == false`). |
| EPIC HERO | 220 | **C only** (cosmetic suffix strip) | ❌ | `40k/autoloads/ArmyListManager.gd:1026-1029` — only used to strip the "– Epic Hero" suffix from a parsed name string. **No engine branch enforces that EPIC HERO units cannot have Enhancements** and **none enforces that EPIC HERO units cannot be attached as the second character to a unit already carrying a CHARACTER**. | **Launch-blocker gap.** Wahapedia core: "Epic Heroes cannot be given Enhancements." `ArmyListManager.validate_army_construction_points` at `:1275-1304` validates only that the bearer has `CHARACTER` — it does not check that the bearer is **not** `EPIC HERO`. |
| INFANTRY | 935 | **W** | ✅ | `40k/autoloads/TerrainManager.gd:26,271,573-684` (wall traversal `INFANTRY:false → can pass through, VEHICLE/MONSTER:true → blocked`); `40k/autoloads/RulesEngine.gd:1335,2173,3471,6164` (Ded Glowy Ammo target gating, Anti-INFANTRY weapon parsing); `40k/autoloads/SecondaryMissionManager.gd:1208,1690`. | Branches correctly. Note: terrain `can_move_through` dictionary only declares INFANTRY/VEHICLE/MONSTER — BEAST/SWARM/MOUNTED are not represented in terrain tables (defaults to false → "blocked"). See divergence #2. |
| BEAST | 21 | **❌ absent** | 🐛 | No engine branch found. Codebase-wide grep `"BEAST"` in `40k/autoloads/`, `40k/phases/`, `40k/scripts/` returns 0 matches. | Cover save 3+ cap should be INFANTRY/BEAST/SWARM-only per Wahapedia; current implementation is universal (see divergence #1). BEAST-specific Pile In aura and ruin-floor access also unimplemented. |
| SWARM | 13 | **❌ absent** | 🐛 | No engine branch. Codebase-wide grep `"SWARM"` returns 0 matches. | Same as BEAST. Without SWARM branching, swarm models cannot get the cover-cap exemption nor the upper-Ruin-floor allowance (the latter doesn't exist anyway — see CHARACTER section). |
| MOUNTED | 143 | **W** (limited) | ⚠️ | `40k/autoloads/FactionAbilityManager.gd:1241` (Here Be Loot — "Orks INFANTRY/MOUNTED/WALKER" gating); `40k/autoloads/FactionStratagemLoader.gd:518` (stratagem condition parsing). | MOUNTED is recognized in **two** call sites only. No general movement/cover/charge rule keys off MOUNTED. Most 10e MOUNTED-specific abilities (e.g. some +1 to wound stratagems) would not gate. |
| CAVALRY | 0 in catalogue (10e has retired this; replaced by MOUNTED in most contexts) | **❌ absent** | ✅ (correctly absent) | No engine branch. The CAVALRY keyword does not appear in Wahapedia's current 10e datasheet keyword universe per `keywords.json` (zero hits). | Not a defect: 10e replaced CAVALRY with MOUNTED. Audit prompt's mention of CAVALRY is legacy. |
| BIKE | 0 in catalogue (10e folded into MOUNTED for many; "JUMP PACK" / "MOUNTED" used) | **❌ absent** | ✅ (correctly absent) | No engine branch. BIKE is not a 10e datasheet keyword in the corpus (`keywords.json` 0 hits). | Not a defect; legacy in audit prompt. |
| VEHICLE | 1048 | **L** | ✅ | `40k/autoloads/RulesEngine.gd:1030,1805,2639,3350,4063,4815,4823,4980,8554,8916` (BGNT, Anti-VEHICLE, target-eligibility); `40k/autoloads/TerrainManager.gd:27,272,573-684` (wall blocking); `40k/autoloads/SecondaryMissionManager.gd:1210,1715`; `40k/phases/MovementPhase.gd:143,5979`; `40k/phases/ChargePhase.gd:1180,2744`. Live: `RulesEngine.unit_has_keyword(U_CALADIUS_GRAV-TANK_E, "VEHICLE") == true`. | BGNT helper `big_guns_never_tire_active` correctly reads `flags.in_engagement` and the keyword (live test on `U_GHAZGHKULL_THRAKA_A`: returns `false` because Ghazghkull is not currently in ER, even though he is MONSTER — branch logic correct). |
| MONSTER | 111 | **L** | ✅ | Same call sites as VEHICLE (BGNT pairs the two). `40k/autoloads/RulesEngine.gd:4815,4980`; `40k/scripts/AIDecisionMaker.gd:1971,2043,4082,8340,8527`; `40k/phases/MovementPhase.gd:5979`. Live: `RulesEngine.is_monster_or_vehicle(U_GHAZGHKULL_THRAKA_A) == true`. | BGNT and Anti-MONSTER weapons branch correctly. |
| PSYKER | 184 | **❌ absent** | 🐛 | No engine branch. Codebase-wide grep for `"PSYKER"` matches only a comment in `40k/autoloads/UnitAbilityManager.gd:1278` (a description string for a Weirdboy ability). No `unit_has_keyword(_, "PSYKER")` call. No stratagem/enhancement gating reads PSYKER. | **Launch-blocker gap.** Many enhancements & stratagems are PSYKER-only ("a PSYKER model in your army"). With no PSYKER gating, those rules cannot enforce eligibility. Test fixture at `40k/tests/unit/test_formations_phase.gd:677` uses `"PSYKER"` to set up data, but no engine consumer reads it. |
| BATTLELINE | 92 | **W** (parser-only) | 🐛 | Only consumer: `40k/autoloads/FactionStratagemLoader.gd:466,516` — used to translate the literal token "battleline" in stratagem condition text into a `keyword:BATTLELINE` filter. No mission-scoring code branches on BATTLELINE. | **Launch-blocker gap.** 10e has multiple secondary missions that score on BATTLELINE units holding objectives (e.g. "Behind Enemy Lines" Battleline-only variants in some mission packs). `40k/autoloads/SecondaryMissionManager.gd` does not branch on BATTLELINE — `is_infantry`, `is_vehicle`, `is_monster`, `is_character` flags are computed at line 1207-1210 but **no `is_battleline`**. |
| FLY | 482 | **L** | ✅ | `40k/autoloads/TerrainManager.gd:547` (cross-wall override); `40k/autoloads/RulesEngine.gd:5709,6716,6759,7597-7670` (charge over models, fight pile-in, can fly over AIRCRAFT, etc.); `40k/phases/MovementPhase.gd:4954-4956,5788`; `40k/phases/FightPhase.gd:2315-3002` (multi-site pile-in/consolidation gating); `40k/phases/ChargePhase.gd:325,1450,1510,2387,2989`; `40k/scripts/MovementController.gd:2912`; `40k/scripts/ChargeController.gd:909,2600,3190`; `40k/scripts/AIDecisionMaker.gd` (10+ call sites). Live: `"FLY" in U_SHIELD_CAPTAIN_JETBIKE_A.meta.keywords == true`. | Highly wired. Consider this gold-standard for keyword integration. |
| AIRCRAFT | 211 | **L** | ✅ | `40k/autoloads/RulesEngine.gd:6687,6738,7578-7670` (charge restrictions, "non-AIRCRAFT can pile in if has FLY"); `40k/phases/FightPhase.gd:573,747,2314-3002` (cannot be selected to fight); `40k/phases/MovementPhase.gd:144`; `40k/phases/ChargePhase.gd:338,1358,1463`; `40k/scripts/AIDecisionMaker.gd:11831,12082,12155,12223`; `40k/scripts/LineOfSightCalculator.gd:22`. Live: `"AIRCRAFT" in U_WAZBOM_BLASTAJET.meta.keywords == true`. | Solid coverage of the "AIRCRAFT cannot be charged unless charger has FLY" rule. |
| TITANIC | 223 | **W** | ✅ | `40k/autoloads/TurnManager.gd:120` (cannot perform some action while TITANIC); `40k/autoloads/StratagemManager.gd:1858` (some stratagems gated); `40k/autoloads/RulesEngine.gd:5535,8697` (Da Bigger Dey Iz +2 vs TITANIC); `40k/phases/MovementPhase.gd:4954-4956,5831`; `40k/scripts/Main.gd:4933`; `40k/scripts/LineOfSightCalculator.gd:114`. | Wired through movement, stratagem-eligibility, LoS, and OA-26 ability. Did not find a TITANIC-cannot-be-transported branch (`TransportManager`'s `excluded_keywords` is data-driven, so the catalog rather than the engine enforces this — acceptable). |
| TOWERING | 63 | **W** (LoS only) | ⚠️ | `40k/scripts/LineOfSightCalculator.gd:32` — TOWERING units extend visibility through low/medium terrain. | TOWERING-specific terrain LoS interaction is implemented. No other branch (e.g. cannot be placed inside ruins). Likely sufficient for 10e since TOWERING's main rule **is** the LoS interaction; flag for human verification because Wahapedia's TOWERING text specifically interacts with **Ruins** and the engine treats Ruins as a generic terrain type. |
| IMPERIUM | 756 | **C only** (data field) | ⚠️ | Used as a data tag on units (`40k/autoloads/GameState.gd:113,132`, `40k/autoloads/BoardState.gd:39,54`), but **no engine branch reads it**. | The IMPERIUM faction-tree keyword is informational only. Stratagem condition parsing does not recognize it (`FactionStratagemLoader.gd:475-481` only special-cases "adeptus astartes" / "adeptus custodes" / "orks"). Some core stratagems / detachment abilities specify "IMPERIUM units" — those will not gate correctly. |
| CHAOS | 1045 | **C only** (catalog) | ⚠️ | Appears in roster JSONs only. **No engine branch.** Grep returns no `"CHAOS"` matches in `40k/autoloads/`, `40k/phases/`, `40k/scripts/`. | Same issue as IMPERIUM. CHAOS-tree stratagems & enhancements will not gate. (Note: there is currently no Chaos roster fielded, so the immediate impact is P2.) |
| XENOS | (not in catalog; `keywords.json` zero hits) | **❌ absent** | ✅ (correctly absent — keyword not in 10e Wahapedia corpus) | No engine branch. | XENOS isn't a Wahapedia datasheet keyword in the current corpus. Each xenos faction tags its own faction keyword (ORKS, AELDARI, etc.) rather than a parent XENOS. Audit prompt's mention is legacy. |

### 1.2 Ability-form keywords listed in audit prompt (not real keyword keys, included for completeness)

| Token | Form | Engine handling | Notes |
|---|---|---|---|
| LEADER | Ability (not keyword) | Wired via `Datasheets_leader.csv` + `CharacterAttachmentManager.gd` | The audit prompt parenthetically calls it an ability, not a keyword. `CharacterAttachmentManager.can_attach(...)` consumes the leader-attachment table. |
| LONE OPERATIVE | Ability (not keyword) | Wired in `RulesEngine.gd:5370`, `CharacterAttachmentManager.gd` (cannot be attached as Leader) | Per the 2026-05 prior audit, Lone Operative is the canonical 10e standalone-CHARACTER protection mechanism; in-engine handling is correct. |

---

## 2. Faction-keyword (faction-tree) coverage

Wahapedia tags **45 keywords** as `is_faction_keyword=true` in the corpus (the audit prompt expected 26 — the discrepancy is because Wahapedia tags both top-level factions and sub-faction trees like "Plague Legions" / "Blood Angels" / "Ynnari" / "White Scars" as faction keywords).

### 2.1 Engine recognition matrix (faction → engine call sites)

| Faction keyword | Datasheets | Engine recognizes? | Sites |
|---|---:|---|---|
| Adeptus Astartes | 298 | ✅ Yes | `40k/autoloads/FactionAbilityManager.gd:43,138,721,869`; `40k/autoloads/FactionStratagemLoader.gd:476-477,520` |
| Astra Militarum | 233 | ⚠️ Catalog-only (faction code in `FactionStratagemLoader.gd:97-98`) but no engine branch keys off the keyword string | — |
| Heretic Astartes | 167 | ❌ No | — |
| Aeldari | 144 | ⚠️ Faction code mapping only (`FactionStratagemLoader.gd:89-90`) | — |
| Genestealer Cults | 138 | ❌ No | — |
| Legiones Daemonica | 106 | ❌ No | — |
| Orks | 87 | ✅ Yes | `40k/autoloads/FactionAbilityManager.gd:66,73,116,128,157,947,1239,1366,1528,1738`; `40k/autoloads/UnitAbilityManager.gd:2189,3368`; `40k/autoloads/StratagemManager.gd:628,637,1285`; `40k/autoloads/FactionStratagemLoader.gd:480,522` |
| Asuryani | 84 | ❌ No | — |
| Tyranids | 69 | ⚠️ Faction code mapping only | — |
| Necrons | 64 | ⚠️ Faction code mapping only | — |
| T'au Empire | 63 | ❌ No | — |
| Death Guard | 62 | ⚠️ Faction code mapping only | — |
| Thousand Sons | 55 | ❌ No | — |
| World Eaters | 54 | ❌ No | — |
| Drukhari | 47 | ❌ No | — |
| Agents of the Imperium | 47 | ❌ No | — |
| Adeptus Mechanicus | 44 | ❌ No | — |
| Space Wolves | 41 | ❌ No | — |
| Adepta Sororitas | 38 | ❌ No | — |
| Chaos Knights | 37 | ❌ No | — |
| Grey Knights | 31 | ❌ No | — |
| Adeptus Custodes | 31 | ✅ Yes | `40k/autoloads/FactionAbilityManager.gd:80,146`; `40k/autoloads/UnitAbilityManager.gd:2263`; `40k/autoloads/FactionStratagemLoader.gd:478-479,521` |
| Imperial Knights | 28 | ❌ No | — |
| Blood Angels | 26 | ❌ No | — |
| Deathwatch | 23 | ❌ No | — |
| Leagues of Votann | 22 | ❌ No | — |
| Dark Angels | 19 | ❌ No | — |
| Black Templars | 19 | ❌ No | — |
| Emperor's Children | 19 | ❌ No | — |
| Harlequins | 16 | ❌ No | — |
| Ultramarines | 13 | ❌ No | — |
| Anathema Psykana | (not in `keywords.json` faction list — sub-keyword) | ✅ Yes | `40k/autoloads/FactionStratagemLoader.gd:523` (excluded-keyword parsing) |
| Ynnari, Plague Legions, Scintillating Legions, Legions of Excess, Blood Legions, Adeptus Titanicus, Imperial Fists, Iron Hands, Salamanders, Raven Guard, White Scars, Blood Ravens, Unaligned, Unaligned Forces | varies | ❌ No engine branch | — |

**Summary:** Of 45 Wahapedia faction keywords, the engine has **3 fully-wired** (Adeptus Astartes, Orks, Adeptus Custodes) and **6 with faction-code mapping but no keyword-string branch** (Aeldari, Astra Militarum, Tyranids, Necrons, Death Guard, plus Anathema Psykana for stratagem exclusion). **36 faction keywords have zero engine recognition.** Catalog-only factions cannot enforce faction-keyword-gated stratagems / enhancements / detachment abilities.

This aligns with the inventory finding (1.4) that only 3 of 26 factions have rosters; faction-keyword wiring tracks active rosters directly.

---

## 3. Spot-check: 20 random flavor keywords (orphan check)

Random sample (seed=42) from non-faction-keyword, non-rules-bearing pool:

| # | Keyword | `40k/autoloads,phases,scripts` literal hits | Verdict |
|---|---|---:|---|
| 1 | Earthshakers | 0 | clean |
| 2 | Warlocks | 0 | clean |
| 3 | Battlesuit | 0 | clean |
| 4 | Harald Deathwolf | 0 | clean |
| 5 | Firestrike Servo-turrets | 0 | clean |
| 6 | Nobz on Warbikes | 1 (comment in `UnitAbilityManager.gd:818` — "OA-26 Consolidation distance"; comment, not keyword string-equality) | clean (not orphan) |
| 7 | Manticore Platform | 0 | clean |
| 8 | Wolf Priest | 0 | clean |
| 9 | Morvenn Vahl | 0 | clean |
| 10 | Techmarine | 0 | clean |
| 11 | Ravenwing Command Squad | 0 | clean |
| 12 | Vortex Missile Strongpoint | 0 | clean |
| 13 | Platoon | 0 | clean |
| 14 | Whirlwind Scorpius | 0 | clean |
| 15 | Rubricae | 0 | clean |
| 16 | Boss Zagstruk | 3 (comments only — `UnitAbilityManager.gd:63,83,294`, all OA-23 documentation comments referencing the named unit) | clean (not orphan) |
| 17 | Morkanaut | 7 (comments only — OA-28, OA-41 documentation in `UnitAbilityManager.gd`, `FactionAbilityManager.gd`, `RulesEngine.gd`, `MovementPhase.gd`) | clean (not orphan) |
| 18 | Infernal Enrapturess | 0 | clean |
| 19 | Wolf Guard Pack Leader with Jump Pack | 0 | clean |
| 20 | Sicaran Venator | 0 | clean |

**Result: 0 of 20 flavor keywords are referenced by engine logic as keyword string-equalities.** The 11 hits across rows 6/16/17 are inline comments documenting which unit a feature was implemented for; none gate code on the literal flavor keyword. Flavor keywords are handled correctly as data tags only.

---

## 4. Live-validation transcript

**Bridge state:** `mcp__godot-mcp-bridge__ping` → `pong: 5348811, engine: 4.6-stable (steam)`. `get_current_phase` → `FIGHT, round 1, active player 2`. Both rosters loaded (Adeptus Custodes vs Orks).

| Test | Method | Result |
|---|---|---|
| Recognize MONSTER on `U_GHAZGHKULL_THRAKA_A` | `RulesEngine.is_monster_or_vehicle(unit)` | ✅ `true` |
| Recognize VEHICLE on `U_CALADIUS_GRAV-TANK_E` | `RulesEngine.unit_has_keyword(unit, "VEHICLE")` | ✅ `true` |
| BGNT not active when MONSTER not in ER | `RulesEngine.big_guns_never_tire_active(U_GHAZGHKULL)` | ✅ `false` (correct; `flags.in_engagement` is currently false) |
| Recognize FLY on `U_SHIELD_CAPTAIN_JETBIKE_A` | `"FLY" in unit.meta.keywords` | ✅ `true` |
| Recognize AIRCRAFT on `U_WAZBOM_BLASTAJET` | `"AIRCRAFT" in unit.meta.keywords` | ✅ `true` |
| 9e Look-Out-Sir helper truly removed at runtime | `RulesEngine.has_method("is_character_protected_from_targeting")` | ✅ `false` (correctly gone post-commit 8749eb4) |

Five of the prompt's six requested live-validation paths require driving an action through a phase (BGNT-in-ER, INFANTRY-climb-Ruin, Look-Out-Sir-redirect, Precision-allocation, Battleline-scoring). The current scene is mid-Fight with one available action `APPLY_MELEE_SAVES`; reproducing those scenarios requires a windowed scenario per `CLAUDE.md` validation rule. Per the audit's "MCP single-instance" constraint and the Fight-Phase mid-action lock, those scenarios were not driven here:

> **LIVE-VALIDATION SKIPPED:** BGNT-in-ER live test not run — current Fight Phase blocks shooting actions; requires a separate Shooting-Phase windowed scenario.
>
> **LIVE-VALIDATION SKIPPED:** Upper-Ruin-floor allow-INFANTRY/reject-VEHICLE not run — engine does not implement upper-floor occupancy at all (`TerrainManager.gd:461` "units stay on the ground floor"), so test cannot succeed.
>
> **LIVE-VALIDATION SKIPPED:** Look-Out-Sir-redirect — already-removed mechanic; no live affordance to validate. Redirect to attached-CHARACTER bodyguard absorption is the 10e replacement and was verified by the prior audit.
>
> **LIVE-VALIDATION SKIPPED:** Precision-allocation through bodyguard — current Fight Phase has no Precision-tagged weapon being assigned; requires fixture.
>
> **LIVE-VALIDATION SKIPPED:** Battleline scoring differential — `is_battleline` flag not computed (see divergence #4), so there is nothing to validate; non-existence is the finding.

Three keyword-recognition / helper-existence checks were live-validated and pass.

---

## 5. Top-5 invisible features (CHARACTER…all-keywords audit)

1. **EPIC HERO enhancement-bearer block.** `40k/autoloads/ArmyListManager.gd:1275-1304` validates Enhancement bearers must be CHARACTER but does **not** also require `EPIC HERO not in keywords`. With 220 EPIC HERO datasheets in the corpus and Wahapedia's "Epic Heroes cannot be given Enhancements" rule, an army roster could pass validation with an Epic Hero carrying an enhancement.
2. **PSYKER-only stratagem/enhancement gating.** `40k/autoloads/StratagemManager.gd` and `Enhancements.csv` describe many "PSYKER model" eligibility constraints. With zero `unit_has_keyword(_, "PSYKER")` call sites, the gate cannot trigger — these would either always-allow or always-deny depending on the parser default.
3. **BATTLELINE secondary-mission scoring.** `40k/autoloads/SecondaryMissionManager.gd:1207-1210` builds `is_infantry`, `is_vehicle`, `is_monster`, `is_character` flags but lacks `is_battleline`. Mission packs that score Battleline-only objectives cannot differentiate.
4. **IMPERIUM / CHAOS faction-tree gating.** Many cross-faction stratagems specify "IMPERIUM units" or "CHAOS units". `FactionStratagemLoader.gd` does not parse these tokens. Affected stratagems load but their eligibility check defaults open.
5. **BEAST / SWARM keyword exemptions.** Cover-cap, terrain-traverse, and pile-in aura rules that cite BEAST/SWARM cannot fire — the keywords have zero engine call sites despite 21+13 datasheets.

---

## 6. Top-5 divergences (vs Wahapedia)

1. **Cover save 3+ cap is now universal, not INFANTRY/BEAST/SWARM-only.** `40k/autoloads/RulesEngine.gd:3700-3706` removed the keyword gate in commit `6958cff` (2026-05-05). The accompanying comment claims "the rule is universal in 10e core; it is NOT keyword-gated". This contradicts Wahapedia's published Benefit of Cover text (which is keyword-gated to INFANTRY/BEAST/SWARM in the Designers' Commentary's restatement and in the Boarding Actions/standard terrain rules). This is a **regression** vs the 2026-05 audit's verified-✅ state (overview line 87). Recommend: re-verify the rule text against current Wahapedia and either restore the keyword gate or document the override. Marked ❓ for human resolution; I was unable to fetch the exact rule text from Wahapedia in this session (404/truncation). 🐛
2. **Terrain `can_move_through` only enumerates INFANTRY/VEHICLE/MONSTER.** `40k/autoloads/TerrainManager.gd:25-29,270-274` use a 3-key dictionary. BEAST, SWARM, MOUNTED, TITANIC implicitly default to `false` (blocked). 10e core: BEAST and SWARM behave like INFANTRY for terrain traversal; MOUNTED/CAVALRY have intermediate rules in some terrain types. Current implementation will block BEAST/SWARM units from passing through ruin walls, which is incorrect.
3. **TITANIC cannot be transported — not keyword-enforced.** `40k/autoloads/TransportManager.gd` reads `excluded_keywords` from transport data; the catalog can list "TITANIC" or "MONSTER" or specific keywords, but the engine itself does not enforce a hardcoded "TITANIC cannot embark" rule. If a roster JSON omits the excluded-keyword list, a TITANIC unit could be embarked. Wahapedia: TITANIC universally cannot embark in transports. Recommend: add a hardcoded `TITANIC` rejection in `TransportManager.can_embark` regardless of the catalog's `excluded_keywords` list.
4. **No `is_battleline` derivation in scoring path.** `40k/autoloads/SecondaryMissionManager.gd:1207-1210` derives 4 type-flags from keywords but omits BATTLELINE. Wahapedia 10e mission packs include several Battleline-only secondaries.
5. **`MOUNTED` recognized in only 2 sites; `WALKER` in only 2.** `40k/autoloads/FactionAbilityManager.gd:1241` couples them with INFANTRY for the Orks "Here Be Loot" check. There is no general rule path that gates by MOUNTED. Stratagems like "Suppressive Fire" (MOUNTED+VEHICLE) cannot enforce MOUNTED eligibility.

---

## 7. Hard-coded unit-name lists where a keyword should be used

| Location | Pattern | Should branch on |
|---|---|---|
| `40k/autoloads/UnitAbilityManager.gd:2536-3143` | Long chain `if ability_name == "Sentinel Storm" / "Sanctified Flames" / "Throat Slittas" / ...` (~20 named ability handlers) | This is **acceptable** — abilities are named entities, not keywords. Not a defect. |
| `40k/autoloads/FactionAbilityManager.gd:463,1132` | Comments like `# OA-20: Prophet of Da Great Waaagh! — Crit Hit on 5+ while Waaagh! active (Ghazghkull leading)` — actual gating reads the ability dict, not the unit name. | OK — keys off ability presence, not unit name. |
| `40k/autoloads/RulesEngine.gd:3681-3692` (Waaagh! Banner aura) | `_unit_has_waaagh_banner` checks for ability name `"Ghazghkull's Waaagh! Banner (Aura)"`, not for a Ghazghkull unit-id. | OK — ability-name match is faction-data-portable. |
| `40k/autoloads/GameState.gd:621` | `if name.to_lower().contains("redeploy") or name == "Phantasm" or name == "Red Corsairs":` | ⚠️ **Hard-coded stratagem-name list** for redeploy detection. Should branch on a `meta.effect_type` field or a stratagem-tag instead of the literal stratagem names. Not a keyword issue per se but a fragile-pattern instance. |
| `40k/phases/MovementPhase.gd:368,2097,6354` | `if ability_name == "Thievin' Scavengers" ... / "Da Jump"` | OK — ability names. |
| `40k/phases/CommandPhase.gd:285,287` | `FEARLESS / AND THEY SHALL KNOW NO FEAR` | OK — ability names. |

**Verdict:** No engine-rule that **should** branch on a keyword is currently hard-coding a unit-name list instead. The one fragile-list pattern (`GameState.gd:621`) is in stratagem-name space, not keyword space, and is out of scope for this audit (refile against `04_stratagems.md`).

---

## 8. Counts summary

### 8.1 Rules-bearing keyword tier × correctness

| Tier | ✅ matches | ⚠️ partial | ❌ absent | 🐛 diverges | ❓ ambiguous | Total |
|---|---:|---:|---:|---:|---:|---:|
| L (live-validated) | 5 | 0 | 0 | 0 | 0 | 5 |
| W (wired) | 4 | 2 | 0 | 0 | 0 | 6 |
| C (code only) | 0 | 2 | 0 | 1 | 0 | 3 |
| Absent | 2 (correctly) | 0 | 3 | 2 | 0 | 7 |
| **Total** | **11** | **4** | **3** | **3** | **0** | **21** |

### 8.2 Faction-keyword tier

| Tier | Count |
|---|---:|
| ✅ engine wired | 3 (Adeptus Astartes, Orks, Adeptus Custodes) |
| ⚠️ partial (faction-code mapping but no keyword string-branch) | 6 (Aeldari, Astra Militarum, Tyranids, Necrons, Death Guard, Anathema Psykana) |
| ❌ no engine recognition | 36 |
| **Total Wahapedia-tagged faction keywords** | **45** |

### 8.3 Flavor-keyword orphan check

| Sample size | String-equality hits in engine code | Comment-only mentions | Verdict |
|---:|---:|---:|---|
| 20 | 0 | 11 (across 3 keywords, all OA-* documentation) | clean — no orphan keyword usage |

---

## 9. Cross-references to prior audits (no refile)

- `40k/test_results/audit_2026_05/AUDIT_REPORT.md` — verified phase machinery, Heroic Intervention, Lone Operative, enhancement validation (CHARACTER bearer), Look-Out-Sir 10e behavior, BGNT-in-ER gating, Battle-shock OC=0. **None overlap directly with the keyword-gate gaps surfaced here**, except for the Cover save 3+ cap, where the prior audit's ✅ has since regressed (commit `6958cff`, 2026-05-05) — see divergence #1.
- `.llm/rules-audit.md` — already flagged Lone Operative and Look-Out-Sir; this audit does not refile those.
- `MASTER_AUDIT.md`, `MOVEMENT_PHASE_AUDIT.md`, `FIGHT_PHASE_AUDIT.md` — keyword gating not their primary scope; no overlap.

---

## 10. Top-3 launch-blocker shortlist (this audit's contribution)

1. **PSYKER keyword has zero engine branches.** Multiple PSYKER-restricted stratagems and enhancements cannot enforce eligibility. **Action:** add `unit_has_keyword(unit, "PSYKER")` to `StratagemManager.is_valid_target` and to `ArmyListManager.validate_army_construction_points` (PSYKER-only enhancement bearer check).
2. **EPIC HERO enhancement bearer not gated.** `ArmyListManager.gd:1287-1295` validates CHARACTER but not "and not EPIC HERO". A 220-datasheet population of Epic Heroes can carry enhancements that the rule forbids. **Action:** add an `epic_hero_has_enhancement` warning in the validation loop.
3. **Cover save 3+ cap regression.** `RulesEngine.gd:3700-3706` removed the INFANTRY/BEAST/SWARM keyword gate in commit `6958cff`. If the prior audit (which marked the keyword-gated form ✅ on 2026-05-04) was correct against Wahapedia, this is now incorrect for VEHICLE/MONSTER 3+-save units in cover vs AP 0. **Action:** confirm the rule text against current Wahapedia + Designers' Commentary; if keyword-gated, restore the gate; if universal, remove the prior audit's contradicting record to avoid future audits flipping it back.

---

## 11. Top-3 invisible features (engine-side rules nobody can reach)

1. **TOWERING LoS interaction (`LineOfSightCalculator.gd:32`)** — wired but no UI affordance documents the rule to players; players will not know why they can/can't draw LoS.
2. **`big_guns_never_tire_active` helper (`RulesEngine.gd:4827`)** — wired and live-confirmed but no UI banner / log message announces "BGNT active for this shooter" beyond a `print(...)` to the debug log; players cannot see why the -1 to hit is applied unless they read the Godot debug log.
3. **`_unit_has_ork_loot_keyword` "Here Be Loot" gating (`FactionAbilityManager.gd:1231-1243`)** — the only consumer of MOUNTED in the engine. The gating is correct but the affordance is implicit; only the deferred Sustained Hits 1 benefit shows up at attack resolution time. Not a launch blocker.

---

**End of findings.**
