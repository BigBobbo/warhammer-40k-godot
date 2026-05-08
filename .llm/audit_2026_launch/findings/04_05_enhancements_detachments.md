# Stage 4.5 — Enhancements + Detachment Abilities Findings

**Generated:** 2026-05-06
**Auditor brief:** `.llm/audit_2026_launch/04_data_entities/05_enhancements_detachments.md`
**Universe sources:** `.llm/audit_2026_launch/universe/enhancements.json` (925), `universe/detachment_abilities.json` (283), `40k/data/Detachments.csv` (260)
**Live MCP transcript:** Yes — Godot 4.6 running, faction_p1=Adeptus Custodes/Shield Host, faction_p2=Orks/War Horde, screenshot at `user://test_screenshots/audit_05_enhancements_detachments_state.png`

---

## TL;DR

- **Detachments in CSV:** 260 (audit brief says 261; one row dropped on parse but irrelevant — 0 are `U`-reachable for ~98% of factions because no roster JSON exists).
- **Detachment abilities:** 283 total; **4 are P0** (active rosters). Of those 4, **3 are wired** (Martial Mastery, Get Stuck In, Combat Doctrines) and **1 is absent in code** (Lions of the Emperor / "Against All Odds").
- **Enhancements:** 925 total; **16 are P0** (4 each across the 4 P0 detachments). **0 of 16** P0 enhancements have an effect handler in `UnitAbilityManager.ABILITY_EFFECTS` — the only enhancement effects implemented are the 4 Freebooter Krew enhancements (Da Kaptin, Git-spotter Squig, Bionik Workshop, Razgit's Magik Map), and Freebooter Krew is **not** a P0 detachment (no roster uses it).
- **Detachment-specific stratagems:** 6+6+6+6 = 24 P0; ~half auto-map via `FactionStratagemLoader._map_effects` and run; the other half are loaded as `custom:unmapped` and exposed in the panel but have no game effect.
- **Validator:** `ArmyListManager.gd:1275-1304` correctly enforces 1-per-CHARACTER, 1-of-each-per-army, bearer-must-be-CHARACTER. **Spot-check passed** — see Live-validation section.
- **No army builder UI** for picking enhancements; players must hand-edit roster JSON. The `Adeptus_Custodes_1995_Mar_7.json` roster carries `Admonimortis` on a Shield-Captain via JSON edit; the rule has zero engine effect and the player would never know.
- **Bug — non-breaking spaces in detachment names:** `Adeptus_Custodes_1995_Mar_7.json` stores `"Lions of the Emperor"` (NBSP) but `Detachments.csv` and code constants use plain spaces. `FactionStratagemLoader.load_faction_stratagems` does an exact-string compare at line 150 and silently drops every detachment-stratagem row for that roster. Verified live: `"Lions of the Emperor" == "Lions of the Emperor"` returns `false`.
- **Bug — "Strike Force" rosters:** 3 Ork rosters declare `detachment: "Strike Force"` (a generic placeholder, not in CSV). Same path as above — 0 detachment stratagems load. None of those rosters could be played correctly.

---

## Launchable-Detachment Table

| Detachment | Faction | Ability | Enh | Strat | Launchable | Notes |
|---|---|:---:|:---:|:---:|:---:|---|
| Shield Host | Adeptus Custodes | ✅ wired+UI | 0/4 | 4/6 (auto) | ⚠️ partial | Martial Mastery U-reachable in CommandPhase action menu (`CommandPhase.gd:437-446`); 4 enh have NO handler in `UnitAbilityManager.ABILITY_EFFECTS`; ARCHEOTECH_MUNITIONS auto-mapper grants BOTH `grant_lethal_hits` AND `grant_sustained_hits` instead of letting the player pick — 🐛 divergence |
| Lions of the Emperor | Adeptus Custodes | ❌ absent | 0/4 | 0/6 | ❌ NO | "Against All Odds" never grep-matches in 40k/{autoloads,phases,scripts}; roster also has NBSP issue → 0 stratagems load |
| War Horde | Orks | ✅ wired (passive) | 0/4 | 3/6 (auto) | ⚠️ partial | Get Stuck In is a passive flag set on ORKS units (`FactionAbilityManager.gd:930-955`), consumed by `RulesEngine.gd:8150` for Sustained Hits 1; 4 enh have no handler |
| Gladius Task Force | Space Marines | ✅ wired+UI | 0/4 | 3/6 (auto) | ⚠️ partial | Combat Doctrines U-reachable (`CommandPhase.gd:418-435`); flags consumed in RulesEngine + EffectPrimitives; 4 enh have no handler |
| Strike Force | Orks (3 rosters claim) | ❌ not a real detachment | n/a | 0/6 | ❌ NO | Not in `Detachments.csv`; the 3 Ork rosters using this name silently drop all detachment stratagems |

**≥80% bar (Ability + ≥3.2/4 enhancements + ≥4.8/6 stratagems):** **0 / 4 P0 detachments are launchable.**

---

## Findings rows

### Detachment abilities (P0 = 4)

| Entity ID | Name | Faction / Det | Pri | Depth | Correctness | Evidence | Notes |
|---|---|---|---|---|---|---|---|
| 000008393 | Martial Mastery | AC / Shield Host | P0 | U | ✅ | `FactionAbilityManager.gd:79-97` (config), `:957-1078` (helpers), `CommandPhase.gd:437-446,1313-1361` (action+UI), `RulesEngine.gd` consumes `effect_crit_hit_on` + AP improve flags | Per-fight stance + per-round mastery already verified 2026-05; spot-check live — `is_martial_mastery_available(1)` returns false (we are mid-game, mastery already past round-start) |
| 000008393 | Get Stuck In | ORK / War Horde | P0 | W | ✅ | `FactionAbilityManager.gd:65-71,922-955`, `RulesEngine.gd:8150` (Sustained Hits 1 elevation when value==0) | Live: `is_get_stuck_in_active(2) == true`. Passive — no UI affordance needed |
| 000008393 | Combat Doctrines | SM / Gladius | P0 | U | ✅ | `FactionAbilityManager.gd:42-64,789-916`, `CommandPhase.gd:418-435` (action menu), `EffectPrimitives.gd:154-157` flags, `RulesEngine.gd:3280-3311,6667-6679` consumers | Once-per-battle each, 3 doctrines, all 4 effect flags consumed in code |
| 000008393 | Against All Odds | AC / Lions | P0 | ❌ | ❌ | grep-miss in 40k/{autoloads,phases,scripts}; not in `DETACHMENT_ABILITIES`; no LotE branch in `FactionAbilityManager.gd:781-916` | Per Wahapedia: +1 hit & +1 wound when no other friendly within 6". Solo-buff hook does not exist; would need new aura-distance check at hit/wound roll. **NEW LAUNCH-BLOCKER** |

### Enhancements (P0 = 16)

All 16 P0 enhancements are catalog-known by `Enhancements.csv` but **none are implemented as effect entries** in `UnitAbilityManager.ABILITY_EFFECTS`. The validator at `ArmyListManager.gd:1275-1304` will pass them through, and `UnitStatsCardPopup.gd:124-132` will display the name string in the unit popup — but no rule fires. Live verification (single MCP call against `UnitAbilityManager.ABILITY_EFFECTS`):

```
auric_mantle: false        castellans_mark: false       from_hall_armouries: false   panoptispex: false
follow_me_ladz: false      headwoppas_killchoppa: false kunnin_but_brutal: false     supa_cybork_body: false
artificer_armour: false    honour_vehement: false       adept_of_the_codex: false    fire_discipline: false
superior_creation: false   praesidius: false            fierce_conqueror: false      admonimortis: false

(control: git_spotter_squig: TRUE — Freebooter Krew is implemented)
```

| Detachment | Enhancement | Cost | Pri | Depth | Correctness | Evidence | Notes |
|---|---|---|---|---|---|---|---|
| Shield Host | Auric Mantle | 15 | P0 | C-display | ❌ | `UnitStatsCardPopup.gd:124-132` (label), no `ABILITY_EFFECTS["Auric Mantle"]` | "Each time an attack is allocated to bearer, change Damage to 1" — needs new minus_damage hook tied to bearer model |
| Shield Host | Castellan’s Mark | 20 | P0 | C-display | ❌ | (same) | "Strats targeting bearer's unit cost 1 fewer CP (min 0)" — needs CP-cost hook in `StratagemManager.can_use_stratagem` |
| Shield Host | From the Hall of Armouries | 25 | P0 | C-display | ❌ | (same) | "Bearer's unit melee weapons +1 AP and Twin-linked vs CHARACTER, MONSTER or VEHICLE" — needs conditional-keyword AP+Twin-linked grant |
| Shield Host | Panoptispex | 5 | P0 | C-display | ❌ | (same) | "Once per turn, after deploying or moving, opponent must reveal one Reserve unit" — needs reserve-info reveal action |
| Lions of the Emperor | Superior Creation | 25 | P0 | C-display | ❌ | (same) | "Bearer has 5+ FNP" — `set_effect_fnp` primitive exists; just needs ABILITY_EFFECTS entry |
| Lions of the Emperor | Praesidius | 25 | P0 | C-display | ❌ | (same) | "Bearer's unit has Lone Operative" — needs grant-Lone-Operative |
| Lions of the Emperor | Fierce Conqueror | 15 | P0 | C-display | ❌ | (same) | "+1 to Hit & +1 to Wound when bearer's unit charged this turn" — primitives `plus_one_hit` / `plus_one_wound` exist with charged-unit gate, just needs entry |
| Lions of the Emperor | Admonimortis | 10 | P0 | C-display | ❌ | (same); **ROSTER LIVE-CARRIER** = `Adeptus_Custodes_1995_Mar_7.json` U_SHIELD-CAPTAIN_ON_DAWNEAGLE_JETBIKE_A | "Once per battle, on bearer's death roll D6: 4+ deals D3 mortal wounds to one enemy in 6"" — needs death-trigger hook |
| War Horde | Follow Me Ladz | 25 | P0 | C-display | ❌ | (same) | "Friendly ORKS units within 6" of bearer can re-roll Charge rolls" — aura+reroll-charge primitive needed |
| War Horde | Headwoppa’s Killchoppa | 20 | P0 | C-display | ❌ | (same) | "Bearer's melee weapons get +1 to Wound and Devastating Wounds" — primitives exist (`plus_one_wound`, `grant_devastating_wounds`), just needs entry |
| War Horde | Kunnin’ But Brutal | 15 | P0 | C-display | ❌ | (same) | "Bearer can perform Heroic Intervention up to 6"; +1 Attacks if bearer made a charge or H-Int" — needs HI distance override + conditional A buff |
| War Horde | Supa-Cybork Body | 15 | P0 | C-display | ❌ | (same) | "Bearer has 4+ invuln" — `grant_invuln` primitive exists; just needs entry |
| Gladius | Artificer Armour | 10 | P0 | C-display | ❌ | (same) | "Bearer has 2+ Save" — needs Save-stat override (no primitive yet) |
| Gladius | The Honour Vehement | 15 | P0 | C-display | ❌ | (same) | "Bearer's unit always counts as under Assault Doctrine; in Assault Doc bearer's melee +1 Strength" — needs doctrine override flag |
| Gladius | Adept of the Codex | 20 | P0 | C-display | ❌ | (same) | "After resolving Combat Doctrines selection, gain +1 CP if you selected Devastator/Tactical/Assault" — needs CP-gain hook tied to SELECT_COMBAT_DOCTRINE |
| Gladius | Fire Discipline | 25 | P0 | C-display | ❌ | (same) | "Bearer's unit's ranged weapons get [LETHAL HITS]; under Devastator Doctrine also [SUSTAINED HITS 1]" — primitives exist; just needs conditional entry |

### Detachment-specific stratagems (P0 = 24)

Counts taken live from `StratagemManager._player_faction_stratagems` after the `from_save` flow loaded P1=AC/Shield Host and P2=ORK/War Horde. Both rosters loaded the full 6 detachment stratagems. The auto-mapper at `FactionStratagemLoader.gd:574-718` flags `implemented: true` only when at least one effect-primitive matches the description text.

| Detachment | Stratagem | CP | Auto-mapped effects | impl | Notes |
|---|---|---|---|:---:|---|
| Shield Host | ARCHEOTECH MUNITIONS | 1 | grant_lethal_hits + grant_sustained_hits | ✅ | 🐛 Auto-mapper grants BOTH; rule says player picks ONE — divergence |
| Shield Host | ARCANE GENETIC ALCHEMY | 1 | grant_fnp 4 (vs MW only) | ✅ | Mapper sets generic FNP, not the MW-only restriction — partial |
| Shield Host | UNWAVERING SENTINELS | 1 | minus_one_hit | ✅ | Match |
| Shield Host | AVENGE THE FALLEN | 1 | (custom:unmapped) | ❌ | "+1 A melee, +2 if Below Half-strength" — not auto-mapped, no manual handler in `_mark_custom_implemented_stratagems` |
| Shield Host | MULTIPOTENTIALITY | 1 | fall_back_and_shoot + fall_back_and_charge | ✅ | Match |
| Shield Host | VIGILANCE ETERNAL | 1 | (custom:unmapped) | ❌ | Objective-control persistence after walking off — no primitive exists |
| War Horde | ’ARD AS NAILS | 1 | minus_one_wound | ✅ | Match |
| War Horde | UNBRIDLED CARNAGE | 1 | crit_hit_on 5 | ✅ | Match |
| War Horde | MOB RULE | 1 | (custom:unmapped) | ❌ | Battle-shock removal w/ MOB-unit proximity gate — no handler |
| War Horde | ERE WE GO | 1 | (custom:unmapped) | ❌ | "+2 to Advance and Charge rolls" — no Advance-bonus primitive |
| War Horde | CAREEN! | 1 | (custom:unmapped) | ❌ | Pre-deadly-demise move — Deadly Demise stratagem hook absent |
| War Horde | ORKS IS NEVER BEATEN | 2 | (custom:unmapped) | ❌ | Last-fight death-replay — Fights-on-death hook absent |
| Lions | PEERLESS WARRIOR | 1 | grant_precision (melee) | ✅ | (Loaded only if detachment string matches; NBSP roster issue blocks) |
| Lions | MANOEUVRE AND FIRE | 1 | fall_back_and_{shoot,charge} | ✅ | (same) |
| Lions | SWIFT AS THE EAGLE | 1 | (custom:unmapped) | ❌ | D6" Normal move grant — no primitive |
| Lions | UNLEASH THE LIONS | 1 | (custom:unmapped) | ❌ | Split unit into 1-model units — structural, no primitive |
| Lions | GILDED CHAMPION | 1 | (custom:unmapped) | ❌ | Re-use a "once per battle" ability — no usage-tracking override |
| Lions | DEFIANT TO THE LAST | 1 | (custom:unmapped) | ❌ | Fights-on-death (CHARACTER bonus) — see ORKS IS NEVER BEATEN |
| Gladius | HONOUR THE CHAPTER | 1 | improve_ap + grant_lance | ✅ | Match (both effects fire when description has both) |
| Gladius | ARMOUR OF CONTEMPT | 1 | worsen_ap | ✅ | Match |
| Gladius | STORM OF FIRE | 1 | improve_ap + grant_ignores_cover | ✅ | Match |
| Gladius | ONLY IN DEATH DOES DUTY END | 2 | (custom:unmapped) | ❌ | Fights-on-death |
| Gladius | ADAPTIVE STRATEGY | 1 | (custom:unmapped) | ❌ | Per-unit doctrine override — no override hook |
| Gladius | SQUAD TACTICS | 1 | (custom:unmapped) | ❌ | D6"/6" Normal move grant — same as SWIFT AS THE EAGLE |

**Mapped/unmapped split:** 12 of 24 P0 detachment stratagems auto-map (50%); 12 are loaded but inert.

---

## Live-validation transcript

Game running, P1=AC/Shield Host, P2=ORK/War Horde. (Single MCP instance — could not also test SM/Gladius or Lions in same session; brief permits this.)

```
ping → ok (4.6-stable)
get_current_phase → FIGHT, P2 active, round 1
GameState.factions[1] = {name: "Adeptus Custodes", detachment: "Shield Host", points: 1000}
GameState.factions[2] = {name: "Orks",             detachment: "War Horde",   points: 2000}
FactionAbilityManager.DETACHMENT_ABILITIES.keys() = [Gladius Task Force, War Horde, Freebooter Krew, Shield Host]
                                                                                          ^^^^^^^^^^ Lions of the Emperor MISSING
FactionAbilityManager.FREEBOOTER_ENHANCEMENTS.keys() = [Da Kaptin, Git-spotter Squig, Bionik Workshop, Razgit's Magik Map]
                                                       ^^^ only Freebooter — no Shield Host / WH / Gladius / Lions enhancements registered
FactionAbilityManager.is_get_stuck_in_active(2) = true                          (✅ Get Stuck In on for P2)
FactionAbilityManager.get_player_detachment(1) = "Shield Host"                  (✅ detected)
StratagemManager._player_faction_stratagems[1] = 6 stratagems (Shield Host)     (✅ loaded)
StratagemManager._player_faction_stratagems[2] = 6 stratagems (War Horde)       (✅ loaded)

Per-stratagem implemented flag:
  ARCHEOTECH MUNITIONS=true  ARCANE GENETIC ALCHEMY=true  UNWAVERING SENTINELS=true
  AVENGE THE FALLEN=false   MULTIPOTENTIALITY=true       VIGILANCE ETERNAL=false
  UNBRIDLED CARNAGE=true    'ARD AS NAILS=true           MOB RULE=false
  ERE WE GO=false           CAREEN!=false                ORKS IS NEVER BEATEN=false

ABILITY_EFFECTS lookup for 16 P0 enhancements + 1 control:
  All 16 P0 = false; Git-spotter Squig (Freebooter Krew control) = true.

Test: "Lions of the Emperor" (plain space) == "Lions of the Emperor" (NBSP) → false
Bug confirmed: roster Adeptus_Custodes_1995_Mar_7.json stores NBSP; FactionStratagemLoader.gd:150 exact-match drops every detachment-stratagem row.

UI affordance: Tree-search for "StratagemPanelButton" → exists; Main.gd:28 wires it; StratagemPanel.gd renders Faction/Detachment groups → U-depth confirmed for the 12 implemented detachment stratagems.
```

Screenshot saved at `user://test_screenshots/audit_05_enhancements_detachments_state.png` (in-game state when state-probes fired).

LIVE-VALIDATION SKIPPED for: SM/Gladius doctrine selection panel + Lions/AC nbsp-corrected roster — would need a separate MCP session loading those rosters; confirmed by code-grep instead (Combat Doctrines wired through `CommandPhase.gd:418-435`).

---

## Top launch-blockers

1. **No army builder UI for enhancements.** `Enhancements.csv` has 925 rows; players cannot pick one in-game. Roster edits are JSON-only. Stratagem panel exposes detachment stratagems (`StratagemPanel.gd`), but there is no equivalent enhancement picker; all evidence comes from a label inside `UnitStatsCardPopup.gd:124-132`. **Cited finding:** zero `EnhancementPicker`/`enhancement_dialog` files in 40k/scripts/, 40k/dialogs/, 40k/scenes/.

2. **0 of 16 P0 enhancements have effect handlers.** Even the easy ones (`Supa-Cybork Body` = "4+ invuln", `Superior Creation` = "5+ FNP") use primitives that already exist (`grant_invuln`, `set_effect_fnp`) but no `ABILITY_EFFECTS["..."]` entry was ever added. The framework supports them — the data is missing. (Effect entries for Freebooter Krew exist at `UnitAbilityManager.gd:1006-1026`, proving the path.)

3. **Lions of the Emperor detachment ability is absent.** `Against All Odds` (+1 hit & +1 wound when no other friendly within 6") is not in `DETACHMENT_ABILITIES`, has no helper, and no consumer hook in RulesEngine. One of two AC P0 detachments is unplayable as a result. Compounded by the NBSP-naming bug below — even if implemented, the existing roster JSON would not trigger the load path.

## Top divergences / bugs

1. **🐛 NBSP in roster detachment names** — `Adeptus_Custodes_1995_Mar_7.json` uses ` ` (NBSP) for "Lions of the Emperor". `FactionStratagemLoader.gd:150` exact-string match fails; `FactionAbilityManager.detect_player_detachment` stores the NBSP variant, so `DETACHMENT_ABILITIES` lookup also misses. Fix: normalise NBSP to space at load time in `FactionStratagemLoader.load_faction_stratagems` + `FactionAbilityManager.detect_player_detachment` + `ArmyListManager` import. **Repro:** `"Lions of the Emperor" == "Lions of the Emperor"` returns `false` — verified live this session.

2. **🐛 ARCHEOTECH MUNITIONS auto-mapper grants both keywords** — Wahapedia text says "Select EITHER [LETHAL HITS] or [SUSTAINED HITS 1]". `FactionStratagemLoader._map_effects` adds both whenever both bracketed tokens are present (`:621-626`). Players using the stratagem get both bonuses; should require a player-pick at apply-time. Likely affects similar EITHER-OR text in other auto-mapped stratagems — recommend audit pass on `_map_effects`.

3. **🐛 "Strike Force" detachment** — 3 Ork rosters (`Orks_2000.json`, `Orks_2000_upload.json`, `Orks_Upload_Mar7.json`) declare detachment `Strike Force`, which is **not** an entry in `Detachments.csv`. `FactionStratagemLoader.gd:150` filter silently drops every detachment-specific stratagem (returns only no-detachment rows). Likely a roster-export bug — needs roster repair + load-time validation that detachment exists in `Detachments.csv`.

## Top invisible features

1. **Detachment stratagems with auto-mapped effects.** The 12 `implemented: true` detachment stratagems do work in `RulesEngine`, but there is no test or UI signpost that confirms their effect fired beyond the stratagem panel button click. The flag-stamping branches in `StratagemManager._apply_stratagem_effects` are reachable, but no scenario exercises them.

2. **Detachment ability `Against All Odds` would fire from a faction-specific aura check** that doesn't exist anywhere — even adding the detachment-ability config to `DETACHMENT_ABILITIES` would not be enough; the +1 hit / +1 wound roll-time hook needs adding to `RulesEngine` near the existing modifier accumulator (similar to Oath of Moment treatment in `RulesEngine.gd`).

3. **Combat Doctrines doctrine-conditional stratagem text** — HONOUR THE CHAPTER ("if Assault Doctrine, +1 AP"), STORM OF FIRE ("if Devastator Doctrine, +1 AP"), THE HONOUR VEHEMENT enhancement ("always counts as Assault Doctrine") — the auto-mapper applies the unconditional half but ignores the doctrine conditional entirely. Players would think they got the buff but only get half of it.

---

## Universe scoreboard

| Entity | Total | P0 (active rosters) | P0 implemented | P0 launchable |
|---|---:|---:|---:|---:|
| Detachment abilities | 283 | 4 | 3 (Martial Mastery, Get Stuck In, Combat Doctrines) | 3 |
| Enhancements | 925 | 16 | 0 | 0 |
| Detachment-specific stratagems | varies | 24 | 12 (auto-mapped) | 12 |
| Detachments | 260 | 4 | — | 0 (≥80% threshold) |

**Per-faction launchable detachment count (≥80% bar):**

| Faction | Detachments in CSV | Active rosters | Detachments wired | Launchable |
|---|---:|---|---|---:|
| Adeptus Custodes (AC) | 8 | Shield Host (3 rosters), Lions (1 roster) | Shield Host partial; Lions absent | 0 |
| Orks (ORK) | 13 | War Horde (2 rosters), "Strike Force" (3 rosters — fake) | War Horde partial | 0 |
| Space Marines (SM) | 44 | Gladius (1 roster) | Gladius partial | 0 |
| Other 23 factions | 195 (combined) | none | n/a | 0 |

---

## Spot-check confirmations

- **Validator** at `ArmyListManager.gd:1275-1304` — confirmed reads `meta.enhancements`, enforces 1-per-CHARACTER, 1-of-each-per-army, bearer-must-be-CHARACTER (verified 2026-05; no drift this session).
- **Custodes Shield Host** Martial Mastery — code path intact at `FactionAbilityManager.gd:79-97`, `:957-1078`, `CommandPhase.gd:437-446`.
- **Custodian Guard's Sentinel Storm** + **Praesidium Shield** — separate from detachment audit (unit ability, owned by Stage 4.1 abilities); not refiled here.
- **Ork War Horde Get Stuck In** — confirmed live: `is_get_stuck_in_active(2) == true`; `RulesEngine.gd:8150` consumes via `unit_has_get_stuck_in`.

---

## File cross-reference

- Validator: `40k/autoloads/ArmyListManager.gd:1275-1304`
- Detachment ability config (3 of 4 P0): `40k/autoloads/FactionAbilityManager.gd:42-97`
- Freebooter enhancements config (only working enhancement set, not P0): `40k/autoloads/FactionAbilityManager.gd:106-132`
- Combat Doctrines wiring: `40k/autoloads/FactionAbilityManager.gd:789-916`, `40k/phases/CommandPhase.gd:418-435`
- Martial Mastery wiring: `40k/autoloads/FactionAbilityManager.gd:957-1078`, `40k/phases/CommandPhase.gd:437-446,1313-1361`
- Get Stuck In wiring: `40k/autoloads/FactionAbilityManager.gd:922-955`, `40k/autoloads/RulesEngine.gd:8150`
- Stratagem CSV loader (where NBSP & "Strike Force" bugs hide): `40k/autoloads/FactionStratagemLoader.gd:127-163`, effect mapping `:574-718`
- Stratagem manual-implemented marker: `40k/autoloads/StratagemManager.gd:468-498` (only Freebooter Krew custom handlers)
- Stratagem panel UI: `40k/scripts/StratagemPanel.gd:1-260`, button `40k/scripts/Main.gd:28,368-370,9621-9645`
- Enhancement display in unit popup (only UI signal of an enhancement existing): `40k/scripts/UnitStatsCardPopup.gd:124-132`
- Effect primitives constants: `40k/autoloads/EffectPrimitives.gd:61-103,141-157`
- Roster with `Admonimortis` (live invisible-feature carrier): `40k/armies/Adeptus_Custodes_1995_Mar_7.json` U_SHIELD-CAPTAIN_ON_DAWNEAGLE_JETBIKE_A
- Rosters with fake "Strike Force" detachment: `40k/armies/Orks_2000.json`, `Orks_2000_upload.json`, `Orks_Upload_Mar7.json`
