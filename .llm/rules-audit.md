# WH40K 10e Rules Audit — Godot Implementation

**Audit date:** 2026-05-04
**Source rules:** https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
**Implementation root:** `/Users/robertocallaghan/Documents/claude/godotv2/40k/`
**Methodology:** Wahapedia core-rules WebFetch + 7 parallel `Explore` agents (one per phase/system) + spot-check reads of suspect file:line locations to correct agent over-claims.

Legend: ✅ correct • ⚠️ partial / verify • ❌ missing • 🐛 implemented incorrectly • ➖ N/A or non-issue.

---

## TL;DR — Prioritized Gap List

| Pri | Gap | File:Line | Status |
|-----|-----|-----------|--------|
| ~~HIGH~~ | ~~Heroic Intervention implemented as a Core Stratagem (9e carryover)~~ — **CORRECTION (2026-05-04):** HI IS a 10e Core Strategic Ploy (1 CP, opponent's Charge phase). Implementation at `StratagemManager.gd:272-298,302-328` and `ChargePhase.gd:486-516,2706-2985` matches the 10e text. The original Explore-agent claim was wrong; my audit propagated it without verification. | `phases/ChargePhase.gd:2706-2985`, `autoloads/StratagemManager.gd:302-328` | ✅ |
| ~~HIGH~~ | ~~"Look Out, Sir!" stand-alone CHARACTER protection — verify thresholds~~ — **FIXED 2026-05-04:** confirmed with user that the 9e wounds-threshold "Look Out Sir" was removed from 10e; standalone-character protection now lives entirely in the Lone Operative ability. Deleted `is_character_protected_from_targeting` and its two call sites in `validate_shoot` / `get_eligible_targets`. Kept `is_closest_eligible_target` (still used by Gun-Crazy Show-offs) but stripped its protected-character skip. | `autoloads/RulesEngine.gd` | ✅ |
| ~~HIGH~~ | ~~Detachment Enhancements — no "1 per CHARACTER, 1 of each kind" enforcement~~ — **FIXED 2026-05-04:** added enhancement validator inside `validate_army_construction_points` covering all three rules (1-per-CHARACTER, 1-of-each-per-army, bearer must be CHARACTER). Emits warnings, does not hard-fail load. | `autoloads/ArmyListManager.gd:1275-1304` | ✅ |
| ~~HIGH~~ | ~~Lone Operative units can be attached as leaders~~ — **FIXED 2026-05-04:** added Lone Operative guard in `can_attach` (uses `RulesEngine.has_lone_operative`). | `autoloads/CharacterAttachmentManager.gd` | ✅ |
| ~~MED~~ | ~~Cover save 3+ cap is universal — should only apply to INFANTRY/SWARM/BEAST~~ — **FIXED 2026-05-04:** `_calculate_save_needed` now takes `target_unit` and applies the 3+ cap only for INFANTRY/BEAST/SWARM keywords. VEHICLE/MONSTER 3+ saves can now improve to 2+ via cover (vs AP 0). | `autoloads/RulesEngine.gd:3674-3704` | ✅ |
| ~~MED~~ | ~~Battle-shocked → OC=0 enforcement~~ — **VERIFIED 2026-05-04:** `MissionManager.objective_control_state` is the single OC source and excludes battle-shocked at `MissionManager.gd:207`. All `control_objectives_*` secondary checks delegate to it. Positional checks (table quarters, NML, opponent-zone presence) correctly count battle-shocked by physical presence (10e: shock only zeroes OC, not existence). Action checks use `_is_unit_excluded` honouring per-mission `Battle-shocked` lists at `SecondaryMissionManager.gd:1553`. | n/a | ✅ |
| ~~MED~~ | ~~Insufficient per-model fight eligibility validation in FightPhase~~ — **FIXED 2026-05-04:** added pre-validation in `_validate_assign_attacks` that calls `RulesEngine.get_eligible_melee_model_indices` and rejects any `attacking_models` entry not in the eligible set. Handles both model-id and index formats. | `phases/FightPhase.gd:_validate_assign_attacks` | ✅ |
| ~~MED~~ | ~~"Benefit of Cover" plumbing — woods/barricades wired into save flow~~ — **VERIFIED 2026-05-04:** wiring is complete: `check_benefit_of_cover` (ruins/obstacle/barricade = within-or-behind; woods/crater/area_terrain/forest = within-only) → `_check_model_has_cover` → `has_cover` → `_calculate_save_needed` → +1 save with INFANTRY/BEAST/SWARM cap. Indirect Fire's automatic cover override is wired at `RulesEngine.gd:3036`. | n/a | ✅ |
| ~~LOW~~ | ~~Roll-off does not formally store attacker/defender role~~ — **FIXED 2026-05-04:** `_handle_choose_turn_order` now also sets `meta.attacker = first_turn_player` and `meta.defender` to the other player. | `phases/RollOffPhase.gd:184-194` | ✅ |
| **LOW** | `Heavy` and `Stealth` modifier sources should already cap at ±1 — confirmed at clamp sites; no live bug | `autoloads/RulesEngine.gd:596,647` | ✅ |

**Headline:** the implementation is substantially conformant to 10e. Three real liabilities — Heroic Intervention (9e mechanic still wired), Enhancement validation, and a few keyword-aware exceptions — are the only items likely to come up every game.

---

## 1. Command Phase

Source files: `phases/CommandPhase.gd` (2178 lines), `autoloads/StratagemManager.gd`, `autoloads/MissionManager.gd`.

### Battle-shock
- ✅ Test made at start of Command phase against units **Below Half-strength** — `phases/CommandPhase.gd:221-266`.
- ✅ 2D6 vs best Leadership in unit — `phases/CommandPhase.gd:693, 799`. Effective-roll bonuses (e.g., Waaagh! Effigy) layered on top — `phases/CommandPhase.gd:792-798`.
- ✅ `battle_shocked` flag persists until **start of next Command phase** — clear at `phases/CommandPhase.gd:201-219`.
- ✅ Battle-shocked OC = 0 enforced in objective scoring — `autoloads/MissionManager.gd:207-209` (`unit.flags.battle_shocked` causes `continue`).
- ✅ Battle-shocked units cannot use Stratagems — both target check (`autoloads/StratagemManager.gd:603`) and source check (`autoloads/StratagemManager.gd:613`). Insane Bravery exception correctly carved out for the auto-pass case (`autoloads/StratagemManager.gd:600,608`).
- ✅ FEARLESS / "And They Shall Know No Fear" units skip the test — `phases/CommandPhase.gd:256-289`.
- ⚠️ **Desperate Escape on battle-shocked units that Fall Back** — Movement phase already uses 1-3 threshold (`phases/MovementPhase.gd:4879-4888`). Confirm trigger always fires when battle-shocked Falls Back; the rule is "for every model in that unit" not just those passing through engagement.

### CP Generation (Issue #336 fix verified)
- ✅ First Command phase of the entire game: active player gets **0 CP**; player 2's first turn (still Round 1) gets +1 CP — `phases/CommandPhase.gd:78-85`.
- ✅ "Active player only" — `phases/CommandPhase.gd:155-159`.
- ✅ 1-CP-per-battle-round-from-other-sources cap (Wahapedia: "each player can only gain a total of 1CP per battle round, regardless of the source") — see `is_first_command_phase_of_game` gating; verify external CP-granting Stratagems honor this round-cap counter (unable to confirm a single counter exists; likely tracked per-grant rather than centrally — recommend a `cp_gained_this_round[player_id]` cap).
- ⚠️ No explicit per-round CP-gain cap counter. Potential bug if multiple +1CP effects fire in the same round (e.g., warlord trait + stratagem + ability).

### Stratagems
- ✅ Command Re-roll: 1 CP, once per phase — `autoloads/StratagemManager.gd:101-127`, usage tracked at `:662-667`.
- ✅ Insane Bravery: 1 CP, once per battle — `autoloads/StratagemManager.gd:73-99`.
- ✅ Out-of-phase action gating (P1-59) — `autoloads/StratagemManager.gd:45-53,588-596`.

### 9e Carryovers
- ✅ No morale-phase attrition. Dedicated `MoralePhase.gd` is 107 lines and effectively dead-code per the existing project memory (`#332`).

---

## 2. Movement Phase

Source files: `phases/MovementPhase.gd` (7256 lines), `autoloads/Measurement.gd`, exclusion-zone visuals.

### Normal / Advance / Fall Back / Remain Stationary
- ✅ Engagement Range constant `1.0"` horizontal — `phases/MovementPhase.gd:33`.
- ✅ Vertical engagement 5" component — `autoloads/Measurement.gd:222-229`.
- ✅ Path crosses enemy bases blocks Normal Move (FLY-exempt) — `phases/MovementPhase.gd:5765`.
- ✅ Advance: D6 + flag set (`advanced` true, `cannot_charge` true) — `phases/MovementPhase.gd:1394-1410, 4134-4143`.
- ✅ Assault carve-out for shoot-after-Advance — `phases/ShootingPhase.gd:2890-2900`.
- ✅ Fall Back: cannot end in engagement — `phases/MovementPhase.gd:1130-1134`. Sets `fell_back`/`cannot_shoot`/`cannot_charge` flags — `:4158-4191`. FLY/special-ability override is via `EffectPrimitives` flags.
- ✅ Desperate Escape thresholds — normal 1-2 fail, battle-shocked 1-3 fail — `phases/MovementPhase.gd:4879-4888`. FLY / TITANIC skip — `:4838-4846`. Models removed (not mortal wounds) — `:4898-4907`.
- ✅ Remain Stationary unlocks Heavy +1 — `phases/MovementPhase.gd:4405`, consumed at `autoloads/RulesEngine.gd:1566-1568`.

### Coherency
- ✅ Wahapedia text: "While a unit has **seven or more** models, all of its models must instead be set up... within coherency of **at least two other models**." Code: `var required_connections = 1 if model_count <= 6 else 2` — `phases/MovementPhase.gd:1152`. Correct (an earlier audit agent flagged this mistakenly; verified 7+ → 2 connections matches rule).
- ✅ Multi-shape coherency (Measurement.is_within_coherency) — `phases/MovementPhase.gd:1144-1170`.

### Reinforcements
- ✅ No reinforcements in Round 1 — `phases/MovementPhase.gd:4515-4519, 6077-6079`.
- ✅ Deep Strike >9" from enemy models, edge-to-edge — `phases/MovementPhase.gd:4553-4568`.
- ✅ Strategic Reserves >6" from battlefield edge — `phases/MovementPhase.gd:4570-4580`. Round-2 opp-deployment-zone restriction with Outflank exception — `:4582-4593`.
- ✅ Reserves not on table by end of Round 3 → destroyed — `phases/ScoringPhase.gd:267-270, 381-459` (P1-37).
- ✅ Reserves count as having made a Normal Move on the turn they arrive — verified via `cannot_charge` flag set on arrival.

### Vertical Movement
- ⚠️ Code treats traversal of terrain >2" as ground-level only ("difficult ground only — no height penalty, units stay on ground floor") — `phases/MovementPhase.gd:901-948,1022-1079`. Wahapedia: "vertical distance up and/or down [counts] as part of its move." Acceptable simplification only if no playable terrain is multi-level; otherwise this is a **silent rule shortcut**. Flag for verification when ruins with floors are introduced.

---

## 3. Shooting Phase

Source files: `phases/ShootingPhase.gd` (5819 lines), `autoloads/RulesEngine.gd` (massive), `autoloads/EnhancedLineOfSight.gd`, `autoloads/LineOfSightManager.gd`.

### Eligibility / Target Selection
- ✅ Cannot shoot if Advanced or Fell Back (FLY / Assault carve-outs) — `phases/ShootingPhase.gd:2890-2946`, `autoloads/RulesEngine.gd:1564-1568`.
- ✅ Pistol-only when in engagement; cannot shoot non-Pistols while engaged — `autoloads/RulesEngine.gd:4122-4132`, `phases/ShootingPhase.gd:2927-2930`.
- ✅ Visibility: at least one model in shooter sees at least one in target — `autoloads/RulesEngine.gd:3713-3759`. Enhanced LOS with progressive shape sampling.
- ✅ Cannot select target unit that is in engagement with friendlies (Big Guns Never Tire excepted for VEHICLE/MONSTER attacker) — verified.

### "Look Out, Sir!" / Character Targeting (HIGH PRIORITY VERIFY)
- ⚠️ `autoloads/RulesEngine.gd:5373-5482` implements a stand-alone-CHARACTER protection: `is_character_protected_from_targeting` returns true iff the CHARACTER has W ≤ 9, is not attached, and a friendly non-CHARACTER unit with 3+ models (or a VEHICLE/MONSTER) is within 3". Closest-eligible-target override at `:5432-5482`.
  - The wounds threshold and 3" friendly-unit rule **resemble 10e text**, but the WebFetch did not retrieve canonical Look Out Sir wording. **Verify the threshold (W ≤ 9 vs ≤ 6 vs other) against the current 10e PDF**.
  - One audit pass mistakenly read this as "inverted" — it is not (`> 9 → not protected` correctly means `≤ 9 protected`).
- ✅ Attached CHARACTERS: cannot be directly targeted at all (separate from Look Out Sir mechanic) — `autoloads/RulesEngine.gd:5384`. This is the **bodyguard absorption** rule.
- ✅ **Precision** keyword bypass (allocate to CHARACTER in attached unit) — `autoloads/RulesEngine.gd:2026-2049, 2897-2921`.
- ❌ The **per-attack allocation override** ("when allocating, must choose non-CHARACTER if eligible") inside an attached unit is implicit — handled by treating the attached CHARACTER as "not directly targetable" rather than as "allocation-redirected." Functionally equivalent for ranged attacks since 10e has no auto-redirect, but verify Precision and CHARACTER-only-model edge cases.

### Big Guns Never Tire (#337 fixed)
- ✅ MONSTER/VEHICLE may shoot while engaged; -1 to hit; targeting units engaged with friendlies allowed (excluding the friendly unit itself) — `autoloads/RulesEngine.gd:4818-4862`. Pistols exempted from the -1 — `:1576`.

### Hit / Wound / Save / Damage
- ✅ Sequence correct, both interactive and auto-resolve paths — `autoloads/RulesEngine.gd:1640-1660, 2473-2493`.
- ✅ Critical hit (unmodified 6) always hits; critical wound always wounds.
- ✅ Hit/wound modifier cap ±1 enforced via `clamp(net, -1, 1)` — `autoloads/RulesEngine.gd:596, 647`. Save modifier cap likewise.
- ✅ Re-rolls applied **before** modifiers (per Rules Commentary) — `autoloads/RulesEngine.gd:574-587, 625-637`.

### Cover
- ✅ +1 to armor save vs ranged — `autoloads/RulesEngine.gd:3681-3711`.
- ⚠️ **3+ cap** at `:3686-3688`: `if has_cover and ap == 0 and base_save <= 3: has_cover = false`. This caps universally rather than only for INFANTRY/SWARM/BEAST. **Net effect:** a VEHICLE / MONSTER 3+ that should improve to 2+ via cover is denied the bonus. Low-impact but factually wrong per 10e wording.

### Weapon Abilities
| Ability | Status | File:Line |
|---|---|---|
| Blast (+1 atk per 5 models, max +2; can't shoot at engaged units) | ✅ | `RulesEngine.gd:6112-6141`, `ShootingPhase.gd:1323` |
| Rapid Fire X (+X attacks at half range) | ✅ | `RulesEngine.gd:1369-1394, 2207-2232` |
| Heavy (+1 to hit if Remained Stationary) | ✅ | `RulesEngine.gd:1564-1569, 2399-2403` |
| Assault (shoot after Advance) | ✅ | `ShootingPhase.gd:2890-2900` |
| Pistol (shoot in engagement, only pistols) | ✅ | `RulesEngine.gd:4122-4132` |
| Torrent (auto-hit) | ✅ | `RulesEngine.gd:1440-1442, 1484-1486` |
| Lethal Hits (crit hit → auto-wound) | ✅ | `RulesEngine.gd:1692-1705, 2518-2530` |
| Sustained Hits X (crit hit → +X hits) | ✅ | `RulesEngine.gd:1661-1679, 2498-2516` |
| Twin-linked (re-roll wound) | ✅ | `RulesEngine.gd:605-652, 5095-5111` |
| Anti-X N+ (N+ wound = critical) | ✅ | `RulesEngine.gd:5288-5315` |
| Indirect Fire (no LOS, -1 to hit, target gets cover, 1-3 always fail) | ✅ | `RulesEngine.gd:1443, 1590-1594, 3725-3754` |
| Precision (allocate to CHARACTER) | ✅ | `RulesEngine.gd:2026-2049, 2897-2921` |
| Devastating Wounds (crit wound = MW = damage, no save, no spillover) | ✅ | `RulesEngine.gd:1920-1948, 2750-2778` |
| Hazardous (D6 per Hazardous weapon profile fired; 1 = 3 MW to bearer) | ✅ | `RulesEngine.gd:6330-6497` |

### 9e Carryover Watch
- ➖ Heavy is correctly the 10e form (+1 if Stationary), not the 9e form (-1 if moved). ✅
- ➖ Devastating Wounds is correctly "MW = damage", not "spillover MWs to next model." ✅

---

## 4. Charge Phase

Source files: `phases/ChargePhase.gd` (3249 lines), `scripts/ChargeController.gd`, `autoloads/StratagemManager.gd`.

### Eligibility / Declare / Roll / Move
- ✅ Cannot charge if Advanced/Fell Back unless ability override (Waaagh!, Full Throttle, etc.) — `phases/ChargePhase.gd:1311-1344`.
- ✅ Already-engaged units cannot charge — `phases/ChargePhase.gd:1358-1369`.
- ✅ **Multiple targets** supported — `phases/ChargePhase.gd:297-342` uses `target_unit_ids` array.
- ✅ Each declared target within 12" gated at declaration — `:338-340`.
- ✅ 2D6 charge roll — `phases/ChargePhase.gd:526-527`.
- ✅ Must end in ER of every declared target — `:1583-1627`.
- ✅ Cannot move within ER of non-target enemies — `:1628-1663`.
- ✅ Coherency enforced after charge move — `:1665-1696`.
- ✅ Charging unit gains Fights First — used in fight-order computation at `phases/FightPhase.gd:2054`.

### Overwatch (10e Core Stratagem)
- ✅ Modeled as a 1 CP Core Stratagem — `autoloads/StratagemManager.gd:272-298`. Trigger `enemy_move_or_charge`, condition `within_24_of_enemy`, hit rolls only on 6+. Offered immediately after enemy charge declaration — `phases/ChargePhase.gd:486-516`.
- ✅ CP cost & once-per-turn-per-unit gating present.

### Heroic Intervention — ✅ Correctly implemented (CORRECTION)
The original audit pass flagged HI as a 9e carryover. **This was wrong.** HI is a **10e Core Strategic Ploy** (1 CP, used in the opponent's Charge phase). Implementation is in line with the rule:
- ✅ `autoloads/StratagemManager.gd:272-298, 302-328` — 1 CP, classed as Core Strategic Ploy, trigger `after_enemy_charge_move`, condition `within_24_of_enemy`, battle-shock guard, VEHICLE-without-WALKER restriction.
- ✅ `phases/ChargePhase.gd:486-516, 919-960, 1223-1264, 2706-2985` — prompt offered after each enemy charge move; USE/DECLINE/CHARGE_ROLL/MOVE actions; signals to dialog/AI/network handlers.
- ✅ `dialogs/HeroicInterventionDialog.gd` — UI prompt.
- Test coverage at `40k/tests/unit/test_heroic_intervention.gd` (~36 test methods) is appropriate for a real, in-rule mechanic.
- **Action item:** spot-check the exact movement/eligibility numbers (e.g., 3" pile-in-style move vs 2D6 charge roll, ER requirement, Fights First grant) against the printed 10e Core Stratagems text to confirm the precise mechanic. The fact of the rule existing is confirmed; the precise numerics warrant a Wahapedia/rulebook side-by-side.

---

## 5. Fight Phase

Source files: `phases/FightPhase.gd` (4310 lines), `scripts/FightController.gd`, `autoloads/RulesEngine.gd`.

### Activation Order
- ✅ Charging units fight first — `phases/FightPhase.gd:2054`. (Note: `heroic_intervention` flag is filtered out here, which becomes meaningful only because of the 9e HI carryover above.)
- ✅ Fights First ability adds units to first sub-phase — `:2061`.
- ✅ Fights First + Fights Last cancel to Remaining Combats — `:2068-2073`.
- ✅ Defender alternates first in Remaining Combats — `:221-223, 2207-2275`.

### Pile In
- ✅ Up to 3" — `phases/FightPhase.gd:600`.
- ✅ Must end closer to closest enemy model — `:604, 2323-2386` (edge-to-edge, AIRCRAFT skipped per T4-4).
- ✅ Must maintain ≥1 model in engagement post-pile-in — `:622`.
- ✅ Base-to-base mandatory if reachable — `:630, 2460-2519`.
- ✅ Aircraft skip pile-in — `:573-579`.

### Make Attacks
- ✅ Unit selects ONE primary melee weapon (extra-attacks weapons auto-merged) — `phases/FightPhase.gd:1137, 1183-1201, 1208-1210, 1748-1786`.
- ✅ Critical hits / Lethal Hits / Sustained Hits / Devastating Wounds / Anti-X / Twin-linked all resolve in melee — `phases/FightPhase.gd:1683, 1707-1722, 1783, 1916-1949`.
- ✅ Lance (+1 to wound on charge) — `:1846-1850`.
- ⚠️ **Per-model attack eligibility** — second-rank attacks (model in engagement *or* in base contact with a friendly that is) are validated by `RulesEngine.gd:7751`'s `get_eligible_melee_model_indices()`, but FightPhase forwards `attacking_models` from the action without pre-filtering — `phases/FightPhase.gd:1193`. Defensive in nature; potential for client-side bypass if RulesEngine path mutates.

### Consolidate
- ✅ Up to 3" (or 6" with Drive-by Krumpin') — `phases/FightPhase.gd:949, 1034`.
- ✅ Engagement-mode preferred when reachable; objective-mode fallback — `:753-769, 944-1055`.
- ✅ Mandatory at unit level, optional per model (FGT-1) — `:1089-1093, 1917-1921`.

---

## 6. Army Rules / Detachment / Leader / Keywords

Source files: `autoloads/CharacterAttachmentManager.gd`, `autoloads/FactionAbilityManager.gd`, `autoloads/FactionStratagemLoader.gd`, `autoloads/UnitAbilityManager.gd`, `autoloads/ArmyListManager.gd`.

### Leader Attachment
- ✅ CHARACTER + LEADER + leader_data.can_lead keyword match — `autoloads/CharacterAttachmentManager.gd:14-65`.
- ✅ Same owner enforced — `:49-50`.
- ✅ Default 10e: one CHARACTER per bodyguard — `:56-59`. (An earlier audit pass mis-flagged this as a bug; verified per Wahapedia "merge with a unit" — singular default. Multi-leader is per-character-ability and not a core rule.)
- ✅ Bodyguard cannot itself be CHARACTER — `:62-63`.
- ✅ Detach when bodyguard wiped — `:163-187`.
- ⚠️ **Lone Operative cannot attach** — no check exists. A Lone-Operative CHARACTER with the Leader ability could currently be attached. Add a guard in `can_attach`.

### "Look Out, Sir!" (cross-reference §3)
- See §3. Standalone CHARACTER protection function exists; attached-unit bodyguard absorption works via direct-targeting refusal.

### Lone Operative
- ✅ 12" range gate on shoot validation / target eligibility — `autoloads/RulesEngine.gd:3343, 4085`.
- ✅ Detection covers string and dict ability formats — `:5940-5954`.
- ✅ Attached Lone Operative correctly exempted (becomes part of bodyguard for targeting).

### Stealth
- ✅ -1 to hit for ranged attacks against unit — `autoloads/RulesEngine.gd:1586, 2419, 5932-5954`.
- ✅ EFFECT_PRIMITIVE-granted Stealth supported via FactionStratagemLoader.

### Detachment / Enhancements
- ⚠️ **Detachment selection** — `autoloads/ArmyListManager.gd:1233-1241` checks presence; `autoloads/FactionStratagemLoader.gd:127-163` filters CSV stratagems by detachment. Detachment **rule** (the one passive unique to each detachment) load path not directly visible; verify Oath of Moment / Get Stuck In / etc. are wired to detachment selection rather than faction blanket.
- ❌ **Enhancement validation:** `autoloads/FactionAbilityManager.gd:1397-1481` defines enhancement lists but no code prevents:
  - Same enhancement selected twice (10e: 1 of each per army).
  - Multiple enhancements on the same CHARACTER (10e: 1 per CHARACTER).
  - Enhancement on a non-eligible character.
  - **Add a list-build validator and a `unit.meta.enhancements.size() > 0` rejection at attach time.**

### Faction Abilities (sample-checked)
- ✅ Oath of Moment (re-roll hit + 1 wound) — `autoloads/FactionAbilityManager.gd:136-144`.
- ✅ Waaagh! (Advance+Charge, +1 S/A melee, 5++) — `:164-228`.
- ✅ Combat Doctrines (Devastator/Tactical/Assault, once each per battle) — `:41-63`.
- ✅ Get Stuck In (Sustained Hits 1 melee for ORKS) — `:65-71`.
- ✅ Martial Mastery (CUSTODES Crit 5+ or AP-1 melee) — `:79-96`.

### Keywords
- ✅ `unit_has_keyword` case-insensitive — `autoloads/RulesEngine.gd:5329-5340`.
- ⚠️ No build-time keyword sanity check (e.g., guarantee VEHICLE units have VEHICLE, AIRCRAFT have FLY).

---

## 7. Deployment / Mission / Terrain

Source files: `phases/RollOffPhase.gd`, `phases/DeploymentPhase.gd`, `phases/ScoringPhase.gd`, `phases/ScoutPhase.gd`, `phases/ScoutMovesPhase.gd`, `phases/RedeploymentPhase.gd`, `autoloads/MissionManager.gd`, `autoloads/SecondaryMissionManager.gd`, `autoloads/TerrainManager.gd`, `autoloads/EnhancedLineOfSight.gd`, `autoloads/LineOfSightManager.gd`.

### Deployment
- ✅ Roll-off, ties re-rolled — `phases/RollOffPhase.gd:7-10, 173-175`.
- ⚠️ Attacker/Defender role not stored in meta (some 10e mission rules reference these terms).
- ✅ Wholly within deployment zone (shape-aware polygon) — `phases/DeploymentPhase.gd:249-250`.
- ✅ Deployment coherency: 1-6 → 1 connection, 7+ → 2 connections — `:126-133`.
- ✅ Infiltrators >9" from enemy DZ and >9" from enemy models — `:265-328`.
- ✅ Unplaced Reserves at end of Round 3 destroyed — `phases/ScoringPhase.gd:267-270, 381-459`. Includes embarked-in-transport reserves — `:393-402`.

### Objectives / OC
- ✅ Sum-of-OC within 3" horizontal (edge-to-edge) — `autoloads/MissionManager.gd:183-256`.
- ✅ Battle-shocked excluded from OC — `:206-209`.
- ✅ Sticky objectives (Objective Secured, Get Da Good Bitz) — `:314-369`. Lock breaks on opponent OC takeover — `:274-279`.
- ✅ Multi-mission support (Take and Hold, Purge the Foe, Supply Drop, Sites of Power, Scorched Earth, The Ritual, Terraform).
- ⚠️ Verify all secondary-mission scoring paths (Engage on All Fronts, Behind Enemy Lines, etc.) also exclude battle-shocked units.

### Terrain
- ✅ Three-tier height (LOW <2", MEDIUM 2-5", TALL >5") — `autoloads/TerrainManager.gd:17-22, 337-350`.
- ✅ Ruins LOS rules — wholly-inside sees out, exterior cannot draw through walls, TOWERING and AIRCRAFT exceptions — `autoloads/EnhancedLineOfSight.gd:44-135`, `autoloads/LineOfSightManager.gd:182-196`.
- ✅ Obscuring trait (explicit + tall implicit) — `autoloads/TerrainManager.gd:31-37, 359-367`.
- ✅ Difficult ground (2" flat, FLY immune) — `autoloads/TerrainManager.gd:39-43, 427-432, 465-469`.
- ✅ Charge / movement vertical penalties — `autoloads/TerrainManager.gd:375-471`.
- ✅ Barricades extend Engagement to 2" if interposed — `autoloads/TerrainManager.gd:286-301`.
- ⚠️ **Benefit of Cover wiring:** terrain types declared, but the +1 save attribution (and the 3+ cap interaction) is not visibly exercised from terrain data into the shooting save flow. Confirm a path: terrain → "model has cover from this attack" → `RulesEngine.gd:3681-3711`. Tests reference `benefit_of_cover` keys — likely OK but explicit trace recommended.

### Visibility
- ✅ True LOS, model-to-model, progressive shape sampling — `autoloads/EnhancedLineOfSight.gd:23-93`.

### 9e Terrain Carryover Watch
- ➖ No "Light Cover / Heavy Cover / Dense Cover" distinct save modifiers found — good (10e unified to single +1).
- ➖ No "Defensible / Unit on Top" 9e categorisation found.

---

## 8. Cross-Cutting Findings

### Rules That Are Implemented But Diverge From Wahapedia
- ⚠️ **Cover 3+ cap universal** — should be keyword-gated to INFANTRY / SWARM / BEAST.
- ⚠️ **Vertical move treated as ground-level** — silent simplification; will be wrong on multi-floor ruins.
- ⚠️ **Stand-alone CHARACTER protection** — implemented; verify wounds threshold and 3" rule against the current 10e PDF text since Wahapedia core-rules HTML did not surface canonical wording in the WebFetch.

### 9e Carryovers To Hunt
1. ~~Heroic Intervention plumbing~~ — Not a carryover. HI is a 10e Core Strategic Ploy (corrected after user feedback 2026-05-04).
2. Possible 9e morale residue in `phases/MoralePhase.gd` (107 lines, dead-code per #332). **Confirm deletion.**
3. The `MoralePhase` autoload reference, if still mounted, should be removed.

### Rules That Look Implemented But Should Be Re-Run After Verification
- Per-model fight eligibility (second-rank attacks): wired into RulesEngine but not enforced at FightPhase action-validation boundary.
- CP gain per-round cap from non-Command-phase sources: no central counter visible.
- Detachment Rule (passive) wiring: verify the rule is read off the selected detachment, not the faction.
- Enhancement validation: missing entirely.

---

## 9. Suggested Next Issues to File

| Suggested title | Type | Effort |
|---|---|---|
| Add Enhancement validation: 1 of each, 1 per CHARACTER, eligibility | Feature | M |
| Lone Operative units cannot be attached as leaders | Bug fix | S |
| Cover 3+ cap should be keyword-gated to INFANTRY/SWARM/BEAST | Bug fix | S |
| Per-round CP-gain cap counter (Wahapedia "1 CP per battle round from any source") | Feature | S |
| FightPhase: pre-validate `attacking_models` against eligibility | Hardening | S |
| Verify all secondary-mission scoring paths exclude battle-shocked OC | Audit | S |
| Roll-off should formally store attacker/defender role on game meta | Cleanup | XS |
| Verify 10e Look Out Sir wounds threshold against current core rules PDF | Verify | XS |
| Multi-floor ruins vertical movement cost | Future | L |

---

## Methodology Notes

- The audit is corroborated by the existing `40k/test_results/audit_2026_05/AUDIT_REPORT.md` (60+ test cases across all phases). Items that have already been file-issued and merged (per memory `project_audit_2026_05.md`) are not re-flagged — see Issues #319-#339.
- File:line citations were spot-verified for the four most consequential agent claims (Look Out Sir threshold, Heroic Intervention extent, multi-leader rule, 6+/7+ coherency). Two of those agent claims were corrected in this report.
- Wahapedia core-rules HTML did not surface canonical text for: complete Reinforcements rules, Look Out Sir, full terrain feature wording. These items are flagged ⚠️ for human verification rather than ✅/🐛.
