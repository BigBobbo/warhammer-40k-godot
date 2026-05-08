# 04.04 — Stratagems (findings)

**Generated:** 2026-05-06
**Auditor:** Claude (Opus 4.7)
**Universe:** `.llm/audit_2026_launch/universe/stratagems.json` — 1,478 stratagems
**Active rosters (P0 detachments):**
- Adeptus Custodes / **Shield Host** (`40k/armies/adeptus_custodes.json`)
- Orks / **War Horde** (`40k/armies/orks.json`)
- Space Marines / **Gladius Task Force** (`40k/armies/space_marines.json`)

**Live MCP session at audit time:** Custodes (Shield Host) vs Orks (War Horde), R1 SCORING phase. SM Gladius is NOT in the live game state, so SM/Gladius P0 entries are verified via code/CSV inspection only — `LIVE-VALIDATION SKIPPED: SM Gladius is not the active P1 roster (P1 = Custodes); MCP is single-instance and faction stratagems for SM only load when a SM army is fielded`.

Code touched:
- `40k/autoloads/StratagemManager.gd` (2429 LoC) — registers 12 core stratagems hardcoded (lines 73–414); CP/usage tracking; reactive/proactive query helpers; per-stratagem effect handlers.
- `40k/autoloads/FactionStratagemLoader.gd` (875 LoC) — parses `data/Stratagems.csv` rows into the same shape; auto-maps effect text to `EffectPrimitives` types; otherwise marks `implemented: false`.
- `40k/scripts/StratagemPanel.gd` (147 LoC) — HUD-button + `S` hotkey panel listing every loaded stratagem.
- `40k/scripts/Main.gd:368-370, 4406-4411, 9620-9645` — panel wiring.

---

## Counts

### P0 — `(faction, detachment)` matches an active roster

| Roster | Faction | Detachment | P0 count | Implemented (✅/⚠️/❌/🐛) |
|---|---|---|---:|---|
| Adeptus Custodes | AC | Shield Host | 6 | 4 ✅, 2 ❌ (rejected) |
| Orks | ORK | War Horde | 6 | 2 ✅, 4 ❌ (rejected), 1 🐛 |
| Space Marines | SM | Gladius Task Force | 6 | data-only — load path not exercised live; code inspection: ≤2 of 6 mappable, 1 🐛 |

Plus the 12 core stratagems registered in `StratagemManager._load_core_stratagems()`. **All 18 P0 + 12 core = 30 stratagems are surfaced via the StratagemPanel.**

### P1 — same faction, different detachment

| Faction | P1 count | Distinct other detachments |
|---|---:|---:|
| SM | 249 | 44 |
| ORK | 68 | 13 |
| AC | 38 | 8 |

P1 stratagems CAN be loaded by `FactionStratagemLoader.load_faction_stratagems(faction, detachment_name)` if the army's `meta.detachment` is changed — but each individual stratagem still depends on `_map_effects` finding a known pattern in the effect text or being manually flagged in `_mark_custom_implemented_stratagems` (only 5 hand-marked: GRAB AND BASH, BOARDIN' RUSH, ROLLING LOOT-HEAP, DECK FRAGGERS, KRUMP AND RUN — these 5 are all Orks Boarding Actions stratagems, NOT used by any of the 13 standard Orks detachments).

**Status:** P1 entries are **data ready, detachment-gated**. Switching e.g. the Custodes army from Shield Host to "Auric Champions" would surface a new set of 6 stratagems whose `implemented` flag depends purely on whether their effect text auto-parses. **Of the 38 + 68 + 249 = 355 P1 stratagems, the auto-parser handles roughly the same ~50% rate as P0 (estimated 175 ✅ / 180 ❌ rejected — needs sample audit; not deep-audited per the prompt's directive).**

### P2 — catalog only (no roster for that faction)

23 of 26 factions have NO active roster. P2 stratagem totals (top by count):

| Faction | P2 count |
|---|---:|
| CSM | 102 |
| AE  | 94 |
| NEC | 70 |
| TYR | 64 |
| AM  | 62 |
| CD  | 56 |
| DG  | 54 |
| AdM | 54 |
| DRU | 52 |
| LoV | 50 |
| GC  | 48 |
| TS  | 48 |
| TAU | 44 |
| WE  | 44 |
| GK  | 44 |
| EC  | 42 |
| AoI | 38 |
| AS  | 38 |
| QI  | 36 |
| QT  | 36 |

**Status:** all 1,077 P2 stratagems are **data-only**. They cannot be reached without first authoring an `armies/*.json` for the faction, then changing `meta.detachment`. Marked `data-only` per audit prompt.

### Boarding Actions / Challenger / NEW ORDERS variants

`Stratagems.csv` (faction_id='') contains:

- **12 main 10e Core stratagems** — all 12 hardcoded in `StratagemManager._load_core_stratagems()` (lines 73–414): COMMAND RE-ROLL, INSANE BRAVERY, GO TO GROUND, SMOKESCREEN, EPIC CHALLENGE, GRENADE, TANK SHOCK, FIRE OVERWATCH, HEROIC INTERVENTION, COUNTER-OFFENSIVE, NEW ORDERS, RAPID INGRESS.
- **5 Boarding Actions Core stratagems** (type starts with "Boarding Actions"): EXPLOSIVE CLEARANCE, COMMAND RE-ROLL (BA variant), INSANE BRAVERY (BA variant), COUNTER-OFFENSIVE (BA variant), BATTLEFIELD COMMAND. **NONE are loaded** — `StratagemManager._load_core_stratagems()` only registers main-10e versions; the BA versions in CSV are not wired up. ✅ correct (BA mode is not selectable in the game). Similarly `FactionStratagemLoader.gd:153-156, 180-182` explicitly skips any row with `"Boarding Actions" in row.type`.
- **9 Challenger-mode core stratagems** (type starts with "Challenger"): RENEWED FOCUS, OPPORTUNISTIC STRIKE, BURST OF SPEED, FORCE A BREACH, STRATEGIC RETREAT, ALL IN, PIVOTAL MOMENT, GREAT HASTE, HARBOURED POWER. **NONE are loaded.** ✅ correct (Challenger is a special game mode).
- **2 extra duplicate NEW ORDERS rows + 1 duplicate INSANE BRAVERY + 1 COMMAND RE-ROLL + 1 COUNTER-OFFENSIVE** in CSV (Source.csv has multiple rule-pack entries that re-list these). Confirmed at runtime: only 12 core stratagems are registered (`StratagemManager.stratagems.keys()` returned the expected 12, no duplicates). ✅

**Boarding Actions answer to the audit prompt's specific question:** they are NOT always available — they are NOT loaded at all in normal play. No 🐛.

---

## Findings — Core stratagems (P0 — audited each in detail)

`Source.csv` reference: 10e Core Rules.

### Schema for evidence model

- **Depth tiers:** `C` code, `W` wired into phase, `U` UI-reachable, `L` live-validated this session.
- **Correctness:** ✅ ⚠️ ❌ 🐛 ❓.

| Rule | Wahapedia § / Source | Depth | Correctness | Evidence | Notes |
|---|---|---|---|---|---|
| COMMAND RE-ROLL | Core Stratagem | L | ✅ | `40k/autoloads/StratagemManager.gd:101-127` def; `1502` `execute_command_reroll`; `812-856` `get_available_stratagems_for_trigger` (defined-but-orphan, see invisible-features); UI: `StratagemPanel`. **Live this session 2026-05-06**: `use_stratagem(2,"command_re_roll")` → P2 CP 4→3, `effects: [{type: reroll_last_roll}]`; immediate retry rejected with "COMMAND RE-ROLL can only be used once per phase". | ✅ matches rule. Once-per-phase lock works. |
| INSANE BRAVERY | Core Stratagem | L | ✅ | `40k/autoloads/StratagemManager.gd:73-99` def; CommandPhase battle-shock surfacing; AUDIT_REPORT.md ss1 verified 2026-05-04. | ✅ matches rule. Once-per-battle. Bypass for battle-shocked unit (line 600). |
| GO TO GROUND | Core Stratagem | L | ✅ | `StratagemManager.gd:129-156` def; `40k/phases/ShootingPhase.gd:3200` `get_reactive_stratagems_for_shooting`; AUDIT_REPORT.md t2.st1 verified live 2026-05-04. | ✅ matches rule. Reactive after_target_selected. Effect: invuln 6+ + cover. |
| SMOKESCREEN | Core Stratagem | L | ⚠️ | `StratagemManager.gd:158-185` def; `_player_faction_stratagems` does NOT filter by phase in StratagemPanel; AUDIT_REPORT.md ss16 covered effect via direct invocation. **Live 2026-05-06:** `can_use_stratagem(2, "smokescreen", "U_BOYZ_E")` returned `can_use: true` while current phase is SCORING (11) — see Finding F1 below. | ⚠️ Wahapedia v3.4 (Mar 2026) requires "your unit *contains a model with the SMOKE keyword*" — code uses `keyword:SMOKE` on the unit. Since GW v3.4 made SMOKE a model-level keyword, this could under-target if a unit has only some models with SMOKE. ❓ minor. |
| EPIC CHALLENGE | Core Stratagem | L | ✅ | `StratagemManager.gd:187-213` def; `1459` `is_epic_challenge_available`; `40k/phases/FightPhase.gd:1146-1153` natural trigger `result["trigger_epic_challenge"] = true` when fighter selected; AUDIT_REPORT.md ss11 EFFECT VERIFIED. | ✅ matches rule. Trigger plumbed. |
| GRENADE | Core Stratagem | W | 🐛 | `StratagemManager.gd:215-241` def; `1325-1457` `execute_grenade`; `1129-1191` `get_grenade_eligible_units`. **Live 2026-05-04 (AUDIT_REPORT)** ss17: 2 MWs applied. **🐛**: `execute_grenade(player, grenade_unit_id, target_unit_id)` does not validate the **8" range or visibility from grenade unit to target** (Wahapedia "Select one enemy unit within 8" and visible to your unit"). The function applies MWs to whatever target_unit_id is passed. See Finding F2. | 🐛 missing range/visibility validation. |
| TANK SHOCK | Core Stratagem | L | ✅ | `StratagemManager.gd:243-269` def; `1645-1680` eligibility (engagement-range filter); `1682+` `execute_tank_shock`; AUDIT_REPORT.md ss12 EFFECT VERIFIED LIVE. Engagement-range check uses `Measurement.is_in_engagement_range_shape_aware`. | ✅ matches rule. T toughness → D6 5+ → MW (capped at 6). |
| FIRE OVERWATCH | Core Stratagem | L | ✅ | `StratagemManager.gd:272-298` def; `2266-2328` `execute_fire_overwatch` → `RulesEngine.resolve_overwatch_shooting`; AUDIT_REPORT.md ss13 EFFECT VERIFIED LIVE (CP 1→0, hits-on-6 trace returned). Out-of-phase guard (lines 587-596) blocks chained stratagems during overwatch. TITANIC restriction enforced via `not_titanic` condition. | ✅ matches rule incl. v3.3 dataslate addition (TITANIC restriction, "set up" trigger). |
| HEROIC INTERVENTION | Core Stratagem | L | ✅ | `StratagemManager.gd:302-328` def (cp_cost=1 per Balance Dataslate v3.3); ChargePhase `_process_apply_charge_move` natural trigger; AUDIT_REPORT.md ss14/ss22' EFFECT VERIFIED LIVE via `hi_pretrigger.w40ksave` fixture (R1, P2 charges Custodian Guard, P1 USE_HEROIC_INTERVENTION on Telemon, CP 4→3, 2D6 fired). | ✅ matches v3.3 rule (denies charge bonus, not fights_first). |
| COUNTER-OFFENSIVE | Core Stratagem | L | ✅ | `StratagemManager.gd:330-356` def (cp_cost=2); `1543-1609` eligibility; `40k/phases/FightPhase.gd:_process_use_counter_offensive` (line 3391); AUDIT_REPORT.md ss15/ss21' EFFECT VERIFIED LIVE via `co_pretrigger.w40ksave` (P2 CONSOLIDATE → engine emitted `trigger_counter_offensive: true` → P1 CP 4→2 → fight order swap). | ✅ matches rule. |
| NEW ORDERS | Core Stratagem | L | ✅ | `StratagemManager.gd:358-384` def; effect `discard_and_draw_secondary` consumed by SecondaryMissionManager; AUDIT_REPORT.md t2.sc7 EFFECT VERIFIED. once_per_battle. | ✅ matches Crucible mission rule. |
| RAPID INGRESS | Core Stratagem | L | ✅ | `StratagemManager.gd:388-414` def (v3.3 Deep Strike clarification); MovementPhase `_process_use_rapid_ingress` (line 618+) + `_process_place_rapid_ingress_reinforcement` (line 735+); AUDIT_REPORT.md ss18/ss23' EFFECT VERIFIED LIVE via `ri_pretrigger.w40ksave` (R2 P2 MOVEMENT_END natural trigger → P1 CP 5→4 → unit placement). | ✅ matches v3.3 rule. |

**Sub-total:** 12/12 core ✅ except 1 ⚠️ (SMOKESCREEN model/unit keyword nit) and **GRENADE 🐛** missing range validation.

---

## Findings — Custodes Shield Host (P0)

| Stratagem | ID | Phase / Trigger | Depth | Correctness | Evidence | Notes |
|---|---|---|---|---|---|---|
| ARCANE GENETIC ALCHEMY | `faction_ac_shield_host_arcane_genetic_alchemy` | any / after_mortal_wound, 1 CP | L | ✅ | `_apply_stratagem_effects` → `EffectPrimitives.apply_effects([{grant_fnp:4}])`. **Live 2026-05-06:** P1 CP 4→3, `flags.effect_fnp=4` set on Contemptor-Achillus ✓. AUDIT_REPORT ss2 also EFFECT VERIFIED. | ✅. Once-per-phase. |
| ARCHEOTECH MUNITIONS | `faction_ac_shield_host_archeotech_munitions` | shooting / shooter_selected, 1 CP | L | 🐛 | `effects: [{grant_lethal_hits},{grant_sustained_hits}]` from `_map_effects` parser. **Live 2026-05-06:** Both flags applied simultaneously to Contemptor-Achillus (`effect_lethal_hits=true`, `effect_sustained_hits=true`). | 🐛 **Wahapedia text: "Select either the [LETHAL HITS] or [SUSTAINED HITS 1] ability."** Parser regex matches "[LETHAL HITS]" + "[SUSTAINED HITS" both — current code grants BOTH unconditionally, which is mechanically stronger than the rule. See Finding F3. |
| UNWAVERING SENTINELS | `faction_ac_shield_host_unwavering_sentinels` | fight / after_target_selected, 1 CP | L | ⚠️ | `effects: [{minus_one_hit}]`. **Live 2026-05-06:** P1 CP 3→2, `effect_minus_one_hit=true` on Custodian Guard ✓. | ⚠️ The parsed `target.conditions` includes `on_objective` (from "within range of an objective marker you control"). Verified live: condition matched correctly via `unit_matches_target`. **However the rule says "*melee* attack subtracts 1 from the Hit roll"** — implementation uses `MINUS_ONE_HIT` flag which applies to ALL attacks, not just melee, in `RulesEngine`. Scope of `-1 to hit` may not be melee-only. See Finding F4. |
| AVENGE THE FALLEN | `faction_ac_shield_host_avenge_the_fallen` | fight / fight_phase_start, 1 CP | C | 🚫 | `effects: [{type:custom:unmapped}]`, `implemented: false`. **Live 2026-05-06:** dispatch returns `success: false, error: "AVENGE THE FALLEN is not yet mechanically implemented"`. Wahapedia: "+1 Attack to melee weapons" (or +2 if Below Half-strength). | 🚫 NOT IMPLEMENTED. Parser would need a `+1A` / `+N attacks` effect primitive. Below-Half-strength conditional also not supported. |
| MULTIPOTENTIALITY | `faction_ac_shield_host_multipotentiality` | movement / after_fall_back, 1 CP | W | 🐛 | `effects: [{fall_back_and_shoot},{fall_back_and_charge}]`. AUDIT_REPORT ss19 EFFECT VERIFIED LIVE. **🐛 expiry**: `StratagemManager._apply_stratagem_effects` sets `expires = "end_of_phase"` (line 784). Wahapedia text: "**Until the end of your turn**" — flag should persist through Shooting and Charge phases of the same turn. With `end_of_phase`, `on_phase_end(MOVEMENT)` calls `_clear_expired_effects("end_of_phase")` (line 888) which clears the flags before they're needed. | 🐛 expiry too short. Should be `end_of_turn`. See Finding F5. |
| VIGILANCE ETERNAL | `faction_ac_shield_host_vigilance_eternal` | movement / movement_phase_active, 1 CP | C | 🚫 | `effects: [{type:custom:unmapped}]`, `implemented: false`. **Live 2026-05-06:** dispatch returns `success: false, error: "VIGILANCE ETERNAL is not yet mechanically implemented"`. Wahapedia: "objective marker remains under your control even if you have no models within range, until your opponent controls it at the start or end of any turn". | 🚫 NOT IMPLEMENTED. Requires MissionManager objective-control-override hook (none exists). |

**Custodes Shield Host sub-total:** 3 ✅ EFFECT VERIFIED, 2 🐛/⚠️ divergence, 1 🚫 NOT_IMPLEMENTED + 1 🚫 NOT_IMPLEMENTED. **2 of 6 are unusable.**

---

## Findings — Orks War Horde (P0)

| Stratagem | ID | Phase / Trigger | Depth | Correctness | Evidence | Notes |
|---|---|---|---|---|---|---|
| UNBRIDLED CARNAGE | `faction_ork_war_horde_unbridled_carnage` | fight / fighter_selected, 1 CP | L | ✅ | `effects: [{crit_hit_on:5}]`. **Live 2026-05-06:** P2 CP 4→3, `effect_crit_hit_on=5` on Boyz E ✓. AUDIT_REPORT ss7 EFFECT VERIFIED. | ✅ matches rule. |
| ’ARD AS NAILS | `faction_ork_war_horde_’ard_as_nails` | shooting_or_fight / after_target_selected, 1 CP | L | ✅ | `effects: [{minus_one_wound}]`. Target conditions correctly read `[not_keyword:VEHICLE, not_keyword:MONSTER, not_keyword:GROTS, keyword:ORKS, is_target_of_attack]` after #359 fix. **Live 2026-05-06:** P2 CP 2→1, `effect_minus_one_wound=true` on Boyz E ✓. AUDIT_REPORT ss20 EFFECT VERIFIED post #360 fix. | ✅. Reactive in opponent's shooting AND fight phase. Note: parser sets `turn:either` for the `shooting_or_fight` compound — Wahapedia text restricts the shooting trigger to *opponent's* shooting. The fight trigger is "either player's" so the union is roughly correct, but a player could in theory use ’ARD AS NAILS during their *own* shooting phase reactively if any code path called the trigger then (not currently exercised by ShootingPhase). Low-impact ❓. |
| MOB RULE | `faction_ork_war_horde_mob_rule` | command / end_of_command_phase, 1 CP | C | 🚫🐛 | `effects: [{type:custom:unmapped}]`, `implemented: false`. **Live 2026-05-06:** dispatch returns `success: false, error: "MOB RULE is not yet mechanically implemented"`. Wahapedia: "Select one friendly Battle-shocked Orks Infantry unit within 6"; that unit is no longer Battle-shocked." **Additional parser bug:** the target conditions are `[below_starting_strength]`. The CSV target text is "One Mob unit … that contains 10 or more models **and is not Below Half-strength**". The phrase "below half-strength" is in the negation but `_parse_target` line 490 catches it as `below_starting_strength` (positive condition). Inverts the rule. | 🚫 effect not implemented + 🐛 target parser inverts negation. See Finding F6. |
| ’ERE WE GO | `faction_ork_war_horde_ere_we_go` | movement / movement_phase_start, 1 CP | C | 🚫 | `implemented: false`. **Live 2026-05-06:** dispatch rejected. Wahapedia: "Until the end of the turn, add 2 to Advance and Charge rolls". | 🚫 NOT_IMPLEMENTED. Parser needs an `add_N_to_advance_charge` effect; doesn't exist. |
| CAREEN! | `faction_ork_war_horde_careen` | any / after_unit_destroyed, 1 CP | C | 🚫 | `implemented: false`. **Live 2026-05-06:** dispatch rejected. Wahapedia: "Your unit can make a Normal or Fall Back move before its Deadly Demise ability is resolved." | 🚫 NOT_IMPLEMENTED. Requires an after-destroyed move primitive — not in EffectPrimitives. once_per_battle correctly set. |
| ORKS IS NEVER BEATEN | `faction_ork_war_horde_orks_is_never_beaten` | fight / after_target_selected, 2 CP | C | 🚫 | `implemented: false`. **Live 2026-05-06:** dispatch rejected. Wahapedia: "destroyed model can fight after the attacking unit's attacks finish" (delayed-fight effect). | 🚫 NOT_IMPLEMENTED. Requires a "fights-on-death" hook in FightPhase — not present. |

**Orks War Horde sub-total:** 2 ✅ EFFECT VERIFIED, **4 🚫 NOT_IMPLEMENTED**. With Custodes/Orks (the live audit roster), only 4 of 12 detachment stratagems work end-to-end.

---

## Findings — Space Marines Gladius Task Force (P0, code-only inspection)

`LIVE-VALIDATION SKIPPED: SM Gladius is not P1/P2 in current MCP session (Custodes vs Orks). MCP is single-instance; would require restarting Godot with SM army loaded.`

Inspected via the same auto-parser path that produced AC/ORK output:

| Stratagem | csv `id` | Phase | Likely effect parse | Predicted status |
|---|---|---|---|---|
| ADAPTIVE STRATEGY | 000008328003 | command / your | "Select the Devastator/Tactical/Assault Doctrine. Until your next Command phase, that Combat Doctrine is active for that unit instead of any other Combat Doctrine that is active for your army" | 🚫 likely `custom:unmapped` — parser has no per-unit doctrine override primitive, even though `FactionAbilityManager.select_combat_doctrine` exists for the army-wide selection. Effect requires a per-unit override hook in `_apply_stratagem_effects`. |
| ARMOUR OF CONTEMPT | 000008328006 | shooting_or_fight / after_target_selected | "worsen the Armour Penetration characteristic of that attack by 1" | ✅ likely auto-parses to `WORSEN_AP` (FactionStratagemLoader.gd:585-587). Reactive trigger should plug into the `get_reactive_stratagems_for_shooting/fight` flow. |
| HONOUR THE CHAPTER | 000008328002 | fight / your | "melee weapons … have the [LANCE] ability. If your unit is under the effects of the Assault Doctrine … improve the Armour Penetration … by 1 as well." | ⚠️ partial: "[LANCE]" auto-parses to `GRANT_LANCE` (line 632-634); the Assault Doctrine conditional AP improve is likely lost (parser doesn't support conditional doctrine-based effects). |
| ONLY IN DEATH DOES DUTY END | 000008328007 | fight / after_target_selected, 2 CP | "destroyed model can fight after the attacking model's unit has finished making its attacks" | 🚫 likely `custom:unmapped` (same shape as Orks IS NEVER BEATEN — fights-on-death hook absent). |
| STORM OF FIRE | 000008328004 | shooting / your | "ranged weapons … have the [IGNORES COVER] ability. If your unit is under the effects of the Devastator Doctrine, … improve the AP by 1 as well." | ⚠️ partial: "[IGNORES COVER]" auto-parses to `GRANT_IGNORES_COVER` (line 617-618); Devastator Doctrine conditional AP improve lost. |
| SQUAD TACTICS | 000008328005 | movement / opponent / after_enemy_move | "Your unit can make a Normal move of up to D6", or up to 6" instead if Tactical Doctrine is active." | 🚫 likely `custom:unmapped` — auto-parser doesn't recognize "make a Normal move of up to D6" as an effect primitive. No reactive-move primitive exists. |

**Predicted Gladius outcome (when loaded live):** ~2 ✅, ~2 ⚠️ (LANCE/IGNORES_COVER fire but doctrine bonus lost), ~2 🚫. **Confirms the same systemic gaps** (no doctrine-conditional effects, no fights-on-death, no reactive-move).

---

## Cross-cutting findings

### F1 — StratagemPanel does not gate by phase/trigger (🐛 invisible-feature ↔ design defect)

**Files:** `40k/scripts/StratagemPanel.gd:96-141`, `40k/autoloads/StratagemManager.gd:552-640` `can_use_stratagem`.

The `StratagemPanel` `_build_row` validates each stratagem with `strat_manager.can_use_stratagem(_player, sid)` (line 111). `can_use_stratagem` checks: (a) faction ownership, (b) `implemented` flag, (c) effective CP, (d) once-per restrictions, (e) out-of-phase rules, (f) battle-shocked. **It does NOT check `strat.timing.phase` or `strat.timing.trigger`** against the current phase.

**Live 2026-05-06 confirmation:** while current phase = SCORING (`GameState.get_current_phase()` returned 11), `can_use_stratagem(2, "smokescreen", "U_BOYZ_E")` returned `{"can_use": true, "reason": ""}`. The panel would render the row with status ELIGIBLE and an enabled Use button.

The panel's own header comment (line 9-10) says: *"Greyed-out for ineligible (off-phase, insufficient CP, once-per-X exhausted)."* — implementation does not match docstring intent.

**Impact:** A player could use COUNTER-OFFENSIVE (cost 2 CP) outside the Fight phase, or SMOKESCREEN proactively in their own turn, by clicking the panel button. The engine accepts the dispatch and applies the effect (e.g. Smokescreen sets `effect_cover` + `effect_stealth` on the target — see `StratagemPanel _on_stratagem_panel_use_requested` at `Main.gd:9635-9644` which calls `use_stratagem(active_player, stratagem_id)` directly with no trigger context).

**Fix scope:** add a phase/turn/trigger-window check to `can_use_stratagem` OR have `StratagemPanel` use `get_available_stratagems_for_trigger` with the current phase's natural trigger (currently this method is **defined but never called**).

### F2 — GRENADE: no 8" range or visibility check (🐛)

**File:** `40k/autoloads/StratagemManager.gd:1325-1457` `execute_grenade`.

Wahapedia 10e Core: *"Select one enemy unit within 8" and visible to your unit."* 

Implementation: `execute_grenade(player, grenade_unit_id, target_unit_id)` does not range-check `grenade_unit_id` ↔ `target_unit_id` and does not call any LoS/visibility helper. It rolls 6D6, applies MWs at 4+, and consumes the unit's shooting (sets `flags.has_shot=true`). Eligibility for the GRENADE-using unit is enforced (`get_grenade_eligible_units` at line 1129+: GRENADES keyword, not advanced, not fell back, not shot, not in engagement, has alive models), but the *target* is unbounded.

**Impact:** a Boyz unit at (0,0) can throw a grenade at a Custodian Guard at (10000, 10000) for 6D6 mortal wounds. The 8" / visibility constraint is a player-honor system at present.

### F3 — ARCHEOTECH MUNITIONS grants both LETHAL HITS and SUSTAINED HITS (🐛)

**Files:** `40k/autoloads/FactionStratagemLoader.gd:621-626` (effect parser).

Wahapedia text: *"Select either the [LETHAL HITS] or [SUSTAINED HITS 1] ability."* The parser line 621 (`if "[lethal hits]" in t`) and 625 (`if "[sustained hits" in t`) both match independently and append two effect entries. `EffectPrimitives.apply_effects` then sets both flags.

**Live 2026-05-06 confirmation:** after `use_stratagem(1, "faction_ac_shield_host_archeotech_munitions", "U_CONTEMPTOR-ACHILLUS_DREADNOUGHT_H")`, the unit's `flags` dict shows `effect_lethal_hits=true` AND `effect_sustained_hits=true`. The diff explicitly contains both.

**Impact:** Custodes player gets both keywords for 1 CP instead of choosing — strictly stronger than the rule. The "Select either" mechanic isn't surfaced as a UI choice.

**Fix scope:** add a player-choice dialog when this stratagem fires; OR special-case the parser to emit a tagged choice effect.

### F4 — UNWAVERING SENTINELS: -1 to hit applies to all attacks, not melee-only (⚠️)

**Files:** `40k/autoloads/StratagemManager.gd` UNWAVERING SENTINELS effect parsing → `_map_effects` line 599-600 maps "subtract 1 from the hit roll" to `MINUS_ONE_HIT`. This is a global flag in `EffectPrimitives` and is honored in `RulesEngine` for both ranged and melee.

Wahapedia text: *"each time a melee attack targets your unit, subtract 1 from the Hit roll."* — melee-only.

**Impact:** any incoming attack against the affected Custodian unit gets -1 to hit, including ranged. Strictly stronger than the rule.

**Fix scope:** scope-aware `MINUS_ONE_HIT` flag (`effect_minus_one_hit_melee` / `_ranged`), or add a per-effect `scope: melee` field that the parser can set, then have RulesEngine consume scoped variants.

### F5 — MULTIPOTENTIALITY: effect expires too soon (🐛)

**Files:** `40k/autoloads/StratagemManager.gd:782-795` (default `expires = "end_of_phase"` only overridden for GRAB AND BASH); `:880-893` clears `end_of_phase` effects on phase end.

Wahapedia text: *"**Until the end of your turn**, that unit is eligible to shoot and declare a charge in a turn in which it Fell Back."*

Implementation flow: stratagem used in **Movement phase**, sets `effect_fall_back_and_shoot` + `effect_fall_back_and_charge`. `expires = "end_of_phase"` → `on_phase_end(MOVEMENT)` triggers `_clear_expired_effects("end_of_phase")` → flags cleared **before** Shooting / Charge / Fight phases of that same turn.

**Impact:** the stratagem nominally fires (CP deducted, flag set) but the effect is gone before the unit can shoot or charge — i.e., the player pays 1 CP for nothing. AUDIT_REPORT ss19 verified the flag is *set*, not that it survives the phase boundary.

**Fix scope:** add a per-stratagem expiry override in `_apply_stratagem_effects` similar to GRAB AND BASH (`if name=="MULTIPOTENTIALITY": expires = "end_of_turn"`), or wire the `expires` decision through `EffectPrimitives` based on effect type.

### F6 — MOB RULE: target parser inverts negation (🐛)

**Files:** `40k/autoloads/FactionStratagemLoader.gd:490-491` `_parse_target`.

CSV target text: *"One Mob unit from your army that contains 10 or more models **and is not Below Half-strength**."*

The parser checks `if "below half-strength" in inclusive_t: result.conditions.append("below_starting_strength")` (line 490). The "not" qualifier is not detected, so the condition becomes a *positive* `below_starting_strength` requirement instead of `not_below_starting_strength`. Result: a 10+-model Mob unit at full strength is **rejected** as a target; a half-strength one is **accepted** — the inverse of the rule.

The parser also does not handle "contains 10 or more models" — so a Mob with 5 models would still pass.

(MOB RULE is also `implemented: false` so the stratagem currently rejects all dispatches with "not yet mechanically implemented" — but if/when an effect handler is added, the target filter is wrong.)

### F7 — Proactive faction-stratagem trigger plumbing is missing (invisible-feature)

**Files:** `40k/autoloads/StratagemManager.gd:2189-2259` `get_proactive_stratagems_for_phase` defined but never called from any production code (verified by grep). FightPhase `select_fighter` emits `fighter_selected` signal (line 1143) and calls `is_epic_challenge_available` (line 1146) but does NOT query proactive faction stratagems matching trigger=`fighter_selected` — so UNBRIDLED CARNAGE (Orks), STORM OF FIRE (SM, conceptually shooter_selected), HONOUR THE CHAPTER (SM, fighter_selected), ARCHEOTECH MUNITIONS (Custodes, shooter_selected) are not auto-offered when their trigger window opens.

The player must open the StratagemPanel manually and click Use to fire them. Combined with F1 (panel doesn't gate by phase/trigger), this means the trigger-window concept is essentially absent for proactive faction stratagems — they're always-on from the panel's perspective.

**Impact:** depth `C` (code exists for trigger-aware queries) but never `W` (not wired into phases). Players can still use the strategms via the panel, but the rule's "you can use this stratagem when X happens" is not modeled.

### F8 — `get_available_stratagems_for_trigger` is orphan (invisible-feature)

**Files:** `40k/autoloads/StratagemManager.gd:811-856` defined; **zero call sites** in `40k/`. Tests don't even reference it. The infrastructure for trigger-keyed stratagem surfacing exists but is dead code.

### F9 — once-per-battle/turn/phase locks DO survive save/load (regression-spot-check ✅)

**Files:** `40k/autoloads/StratagemManager.gd:2410-2429` `get_state_for_save` / `load_state`; `40k/autoloads/GameState.gd:1007-1012, 1170-1172` invoke them via the snapshot path.

Issue #338 (audit_2026_05) flagged that StratagemManager had no save/load API. The fix is in place: snapshot includes `stratagem_manager.usage_history`, `active_effects`, `_player_faction_stratagems`. ✅ matches AUDIT_REPORT.md t5.sl3 closure status.

---

## Top 10 stratagems at ❌ or 🐛 (all P0)

1. **GRENADE** 🐛 — no 8" range / visibility check (Finding F2). Affects every faction.
2. **ARCHEOTECH MUNITIONS (Custodes)** 🐛 — grants both LETHAL HITS and SUSTAINED HITS instead of "either/or" (Finding F3).
3. **MULTIPOTENTIALITY (Custodes)** 🐛 — flag expires at end of Movement phase, not end of turn; player pays CP for no effect (Finding F5).
4. **AVENGE THE FALLEN (Custodes)** ❌ — `implemented: false`. +1A / +2A-if-below-half-strength not parseable.
5. **VIGILANCE ETERNAL (Custodes)** ❌ — `implemented: false`. Objective-control-override hook absent.
6. **MOB RULE (Orks)** ❌🐛 — `implemented: false` AND target parser inverts "not Below Half-strength" → applies as positive `below_starting_strength` (Finding F6).
7. **'ERE WE GO (Orks)** ❌ — `implemented: false`. +2 to Advance and Charge rolls effect not parseable.
8. **CAREEN! (Orks)** ❌ — `implemented: false`. Reactive move on destruction not modelled.
9. **ORKS IS NEVER BEATEN (Orks)** ❌ — `implemented: false`. Fights-on-death hook absent.
10. **UNWAVERING SENTINELS (Custodes)** ⚠️ — -1 to hit applies to ranged AND melee, rule says melee-only (Finding F4).

(Predicted SM Gladius additions when loaded: ADAPTIVE STRATEGY ❌, SQUAD TACTICS ❌, ONLY IN DEATH DOES DUTY END ❌, STORM OF FIRE ⚠️ partial, HONOUR THE CHAPTER ⚠️ partial.)

## Top 10 detachments where ≥80% of stratagems are missing — these detachments are unplayable

For ALL 23 catalog-only factions (no roster JSON), 100% of their stratagems are 🚫 catalog-only — none of those detachments can be played at all because no army roster exists to switch to them.

For the 3 active factions, the *currently-loaded* detachment count by missing-or-degraded:

| Detachment | Total P0 | ✅ working | 🐛 / ⚠️ | ❌ unimpl. | % working |
|---|---:|---:|---:|---:|---:|
| AC Shield Host | 6 | 3 | 2 | 1 | 50% |
| ORK War Horde | 6 | 2 | 0 | 4 | 33% |
| SM Gladius Task Force | 6 | ~2 (predicted) | ~2 | ~2 | ~33% |

**P1 detachments are 100% unreachable today** — the army.json `meta.detachment` field is the only switch, and there is no in-game UI to change it. So all 38 (AC) + 68 (ORK) + 249 (SM) = 355 P1 stratagems are de-facto invisible. **Effective coverage = 18 P0 + 12 core = 30 of 1,478 = 2.0%.**

## Per-phase scorecard — how many stratagems per phase reach depth `U`

Depth `U` = the player can trigger it through a visible affordance (the StratagemPanel button or KEY_S). Currently the panel surfaces every loaded `implemented:true` stratagem regardless of phase (F1), so:

| Phase / window | Loaded core | Loaded faction (AC + ORK) | Reaches `U` (panel) | Reaches `U` (auto-offered dialog) |
|---|---:|---:|---:|---:|
| Command | 2 (INSANE BRAVERY, NEW ORDERS) | 0 implemented (MOB RULE 🚫) | 2 | 1 (INSANE BRAVERY auto-offered on BS test) |
| Movement | 1 (RAPID INGRESS) | 1 (MULTIPOTENTIALITY) | 2 | 1 (RAPID INGRESS via natural trigger) + MULTIPOTENTIALITY via Fall Back trigger |
| Shooting | 4 (GO TO GROUND, GRENADE, SMOKESCREEN, EPIC CHALLENGE—wait fight) | 2 (ARCHEOTECH MUNITIONS, ’ARD AS NAILS) | 5 | 1 (GO TO GROUND via reactive flow) |
| Charge | 3 (TANK SHOCK, FIRE OVERWATCH, HEROIC INTERVENTION) | 0 | 3 | 3 (all natural-triggered: TS after charge move, FO on declaration, HI after enemy charge) |
| Fight | 3 (EPIC CHALLENGE, COUNTER-OFFENSIVE, GO TO GROUND for fight-section…) wait EPIC CHALLENGE counts | 2 (UNBRIDLED CARNAGE, UNWAVERING SENTINELS) | 5 | 2 (EPIC CHALLENGE on fighter_selected, COUNTER-OFFENSIVE on fight finish) |
| Any phase | 1 (COMMAND RE-ROLL) | 1 (ARCANE GENETIC ALCHEMY) | 2 | 0 (no auto-offer; player must open panel) |

**Bottom line:** ~14 of the 18 P0+core stratagems reach depth `U` via the panel; ~7 also reach via auto-offer dialogs (the natural-trigger code path). The other ~4 (proactive faction stratagems) reach `U` only via the panel because the trigger is not plumbed.

---

## Top 3 launch-blocker gaps

1. **F1 — StratagemPanel doesn't gate by phase/trigger.** Players can fire stratagems at any time. Combined with F2 (GRENADE no range check) and F5 (MULTIPOTENTIALITY expiry mismatch), this is the most player-visible correctness gap. **Fix: add phase/trigger-window check to `can_use_stratagem` or have the panel use `get_available_stratagems_for_trigger`.** Effort: medium.
2. **355 P1 stratagems unreachable; 1,077 P2 stratagems catalog-only.** The faction stratagem auto-loader works, but it is keyed off `armies/*.json meta.detachment`. With only 3 detachments fielded, 96% of the stratagem catalog is dead data. **Fix: implement detachment selection UI when an army is loaded.** Effort: small UI + medium per-detachment-stratagem effect-mapper investment as factions are turned on.
3. **6 of 12 active P0 faction stratagems are `implemented: false`** (AVENGE THE FALLEN, VIGILANCE ETERNAL, MOB RULE, 'ERE WE GO, CAREEN!, ORKS IS NEVER BEATEN). Each requires a new effect primitive (per-unit attack bonus, objective-override, fights-on-death, conditional-move). **Fix: extend `EffectPrimitives` and `FactionStratagemLoader._map_effects`.** Effort: medium per primitive; ~6 primitives needed.

## Top 3 invisible features

1. **`get_available_stratagems_for_trigger` (StratagemManager.gd:811)** — defined, has full filtering logic, **never called.** Trigger-driven stratagem surfacing exists in code but is unwired (F8).
2. **`get_proactive_stratagems_for_phase` (StratagemManager.gd:2189)** — defined, **never called.** Proactive faction stratagems (UNBRIDLED CARNAGE, ARCHEOTECH MUNITIONS, etc.) are invisible to natural game flow; only reachable via the panel (F7).
3. **The 5 hand-marked Boarding-Actions Orks stratagems** (GRAB AND BASH, BOARDIN' RUSH, ROLLING LOOT-HEAP, DECK FRAGGERS, KRUMP AND RUN) at `StratagemManager._mark_custom_implemented_stratagems` (line 478-497) — these have full custom implementation in `_apply_stratagem_effects` and `_clear_stratagem_flags`, but they belong to non-standard Boarding Actions detachments that no current Orks roster uses. The 13 standard Orks detachments don't include any of them. **Code is live, but unreachable from any active roster.**

---

## Methodology + caveats

- **Live MCP path used.** Connected via `mcp__godot-mcp-bridge__ping` (engine 4.6-stable) → `execute_script` to inspect `StratagemManager.stratagems` dict and `_player_faction_stratagems` map → `use_stratagem` to dispatch each P0 stratagem. CP delta and `flags` mutation observed live for 4 implemented faction stratagems (ARCANE GENETIC ALCHEMY, ARCHEOTECH MUNITIONS, UNWAVERING SENTINELS, UNBRIDLED CARNAGE, ’ARD AS NAILS) + 1 core (COMMAND RE-ROLL); 6 unimplemented stratagems verified to reject without CP burn (AVENGE THE FALLEN, VIGILANCE ETERNAL, MOB RULE, 'ERE WE GO, CAREEN!, ORKS IS NEVER BEATEN).
- **Existing AUDIT_REPORT 2026-05-04 evidence reused** for the natural-trigger path of GO TO GROUND, EPIC CHALLENGE, TANK SHOCK, FIRE OVERWATCH, HEROIC INTERVENTION, COUNTER-OFFENSIVE, RAPID INGRESS, GRENADE, SMOKESCREEN — all of which already had `co_pretrigger.w40ksave` / `hi_pretrigger.w40ksave` / `ri_pretrigger.w40ksave` fixture evidence (depth `L`).
- **Screenshot captured this session:** `user://test_screenshots/stratagem_audit_state_after_p0_drive.png` (saved under `Library/Application Support/Godot/app_userdata/40k/test_screenshots/`). Contents: P1 CP=1, P2 CP=1, both reduced from 4; 6 active stratagem effects in `StratagemManager.active_effects` from this session's drives.
- **SM Gladius live path NOT exercised.** Reason logged: the live game state has Custodes vs Orks loaded; faction stratagem load is keyed off the army JSON `meta` block at game start. Switching factions requires restarting Godot with a different army JSON. Code-only inspection is annotated above for the 6 SM stratagems and predicts ~2 ✅, ~2 ⚠️, ~2 🚫 — would need a follow-up live session with `space_marines.json` set as P1 to confirm.
- **P1 / P2 stratagems were enumerated but not deep-audited** per the audit prompt's directive (P1 = "data-only, detachment-gated"; P2 = "list as table, mark data-only without deep audit"). They share the same parser path as P0 — the same auto-mapped effect primitives apply, the same 🚫 list of unsupported primitives applies. Stratagem-specific divergences would surface in a per-detachment audit; spot-checking would require either (a) editing army JSON + restarting Godot, or (b) directly invoking `FactionStratagemLoader.load_faction_stratagems(faction, detachment)` to enumerate parser output.
- **Anti-pattern guard.** No `_check("func X defined", ...)` pin tests written. All ✅ EFFECT VERIFIED claims have a recorded action dispatch + state delta from this session OR an AUDIT_REPORT 2026-05-04 entry that was itself evidence-backed.
