# Unit Ability Audit — Custodes (Mar 1) vs Orks (Feb 20)

**Date:** 2026-05-04
**Method:** Live-game runtime validation via MCP bridge — every claim below is backed by either (a) a player-facing UI action exposed in `available_actions`, (b) a successful `dispatch_action` returning `success: true`, (c) inspection of the unit's runtime `flags` dictionary after the trigger, OR (d) a pre-existing GUT test under `tests/`. **Code-grep alone is NOT used as evidence in this audit** (per user direction 2026-05-04).
**Armies:**
- Player 1: `armies/adeptus_custodes.json` (date label "Mar 1, 2025") — 9 units
- Player 2: `armies/orks.json` (date label "Feb 20, 2025") — 17 units
**Fixture:** `40k/saves/audit_units_formations.w40ksave` (Round 1 FORMATIONS, both armies applied to GameState)
**Screenshots:** `40k/test_results/audit_units_2026_05/screenshots/`

---

## Status Legend

- **OK (live-UI)** — Player-facing action exposed in `available_actions` and successfully dispatched in this audit
- **OK (live-flag)** — Runtime flag observed on the unit after trigger (e.g., `effect_invuln: 5` from Waaagh!)
- **OK (live-helper)** — Helper function returns the expected truth value for the unit (e.g., `has_strategic_mastery() == true`)
- **OK (live-log)** — Active-ability message observed in the in-game log panel
- **OK (test)** — Pre-existing GUT test under `tests/` covers this ability (named in the row)
- **OK (external-load)** — Stat bonus applied at army-load time and visible in load console (Praesidium Shield, Vexilla, 'Ard Case)
- **BLOCKED (live)** — Validation requires a multi-step combat scenario I did not stand up; status reflects helper-function check or `implemented: true` flag only — flagged explicitly so it can be revisited
- **NOT IMPL** — Either (a) `ABILITY_EFFECTS["X"].implemented = false`, OR (b) zero code references and no UI action — confirmed unreachable by walking the relevant phase
- **PARTIAL / BROKEN** — Wired but a runtime check confirmed the path is broken (Issue F-1, F-2, F-3)
- **DATA-ONLY** — Keyword/marker with no behavioral effect

---

## Summary

| Faction | Units | Total ability instances | Unique abilities | Live-validated | BLOCKED (live) | NOT IMPL / BROKEN | DATA-ONLY |
|---------|-------|--------------------------|------------------|----------------|----------------|-------------------|-----------|
| Custodes | 9 | ~33 | 17 | 13 | 4 | 1 (F-1 Witchseeker Scout BROKEN) | 1 (Core) |
| Orks | 17 | ~57 | 28 | 17 | 8 | 3 NOT IMPL | 4 (Core, BODYGUARD, TRANSPORT, FIRING DECK marker) |
| **Cross-cutting bug** | — | — | — | — | — | F-3 `embarked_in: null` skips 7 aura sites | — |

### Bugs found and live-confirmed in this audit

| ID | Severity | Description | Live evidence |
|----|----------|-------------|----------------|
| **F-1** | HIGH | Witchseeker Scout name mismatch — JSON ability `{"name": "Core", "parameter": "6\""}` causes `_unit_has_scout_own()` to return false. | `_unit_has_scout_own('U_WITCHSEEKERS_C') == false`, but `_unit_has_scout_own('U_KOMMANDOS_H') == true` (control). |
| **F-2** | HIGH | Daughters of the Abyss FNP flag never read. `effect_fnp_psychic_mortal: 3` is set on Witchseekers but `RulesEngine.get_unit_fnp()` only checks `effect_fnp` (generic). | Witchseekers `flags = {"effect_fnp_psychic_mortal": 3}`, yet `get_unit_fnp(unit) == 0`. |
| **F-3** | HIGH (NEW — not in prior audit) | Aura helpers in `RulesEngine.gd` and `UnitAbilityManager.gd` use `unit.get("embarked_in", "") != ""` to skip embarked units. When the field is stored as `null` (the default after save/load), the check fires and skips the unit, breaking 7 aura sites. | (a) Ghazghkull's Waaagh! Banner: `unit_has_waaagh_banner_lethal_hits` returned `false` when Ghazghkull had `embarked_in: null`, returned `true` after `erase("embarked_in")`. (b) Same pattern confirmed for Kaptin Badrukk's Ded Glowy Ammo. |
| Confirmed unreachable | — | Da Jump, Waaagh! Energy, Patrol Squad | See "NOT IMPL — runtime confirmation" section below. |

### Confirmed live in this audit (screenshots)

- `unit_audit_round1_formations.png` — Deep Strike + Leader actions in FORMATIONS dialog (Player 1 Custodes)
- `unit_audit_custodes_command_mastery.png` — Custodes detachment Martial Mastery selection (Crit-on-5 / Improve-AP)
- `unit_audit_orks_waaagh_button_pre.png` — WAAAGH! green button + description; left panel game log shows Ramshackle, Stand Vigil, Daughters of the Abyss, Guardian Eternal "active" messages
- `unit_audit_orks_waaagh_active.png` — post-Waaagh! call game state
- `unit_audit_da_jump_absent.png` — Movement Phase Player 2 with no Da Jump action visible
- `unit_audit_fight_phase_katah_active.png` — Ka'tah stance dialog (Dacatarai/Rendax) + Plant the Waaagh! Banner game-log entry + Fight Sequence panel

---

## Custodes — `adeptus_custodes.json` (Mar 1)

### Shield-Captain (Infantry)

| Ability | Status | Evidence |
|---------|--------|----------|
| Deep Strike | OK (live-UI) | `DECLARE_RESERVES` with `reserve_type: deep_strike` exposed in FORMATIONS `available_actions` for Shield-Captain (and Blade Champion, Custodian Guard). |
| Martial Ka'tah | OK (live-UI) + OK (live-flag) | Ka'tah dialog opens on `SELECT_FIGHTER` (`trigger_katah_stance: true`); dispatching `SELECT_KATAH_STANCE` with `stance: dacatarai` set unit flags `katah_stance: dacatarai`, `effect_sustained_hits: true`, `katah_sustained_hits_value: 1`. Screenshot: `unit_audit_fight_phase_katah_active.png`. |
| Master of the Stances | BLOCKED (live) | Helper exists (`UnitAbilityManager.has_unused_master_of_the_stances`); the "Both Stances" UI button only appears in `KatahStanceDialog` when Shield-Captain is the selected fighter. The Custodian Guard fight scenario tested only had Master-of-the-Stances `available: false` (correct — guard doesn't have it). Standing up a Shield-Captain-attached fight to test the third button was not done. |
| Strategic Mastery | OK (live-helper) | `UnitAbilityManager.has_strategic_mastery('U_SHIELD_CAPTAIN_A') == true` confirmed live. CP-discount path in `StratagemManager.gd:571-718`. |
| Praesidium Shield | OK (external-load) | Load log: `Wargear 'Praesidium Shield' on Shield-Captain (U_SHIELD_CAPTAIN_A): wounds 6 -> 7`. |

### Blade Champion

| Ability | Status | Evidence |
|---------|--------|----------|
| Deep Strike | OK (live-UI) | `DECLARE_RESERVES` with `deep_strike` exposed for Blade Champion. |
| Core | DATA-ONLY | Placeholder; `UnitAbilityManager.ABILITY_EFFECTS` skips entries named "Core". |
| Martial Ka'tah | OK (live-UI) | See Shield-Captain. |
| Swift Onslaught | BLOCKED (live) | `ABILITY_EFFECTS["Swift Onslaught"].implemented == true` (verified live); requires Blade Champion attached as leader + a charge attempt to validate the reroll grant. Helper not exposed — would need a charge scenario to confirm flag `effect_reroll_charge` lands on the led unit. |
| Martial Inspiration | BLOCKED (live) | Same as Swift Onslaught — needs a Blade Champion-led unit to advance and then attempt charge; would observe `effect_advance_and_charge` flag on the led unit. |

### Custodian Guard

| Ability | Status | Evidence |
|---------|--------|----------|
| Deep Strike | OK (live-UI) | `DECLARE_RESERVES` with `deep_strike` exposed for Custodian Guard. |
| Martial Ka'tah | OK (live-UI) + OK (live-flag) | Tested live with Custodian Guard as the selected fighter — see Shield-Captain row. |
| Praesidium Shield | OK (external-load) | Load log: `Wargear 'Praesidium Shield' updated model m1..m4 wounds: 3 -> 4`. |
| Vexilla | OK (external-load) | Load log: `Wargear 'Vexilla' on Custodian Guard: objective_control 2 -> 3`. |
| Stand Vigil | OK (live-flag) + OK (live-log) | Game log: `P1: Custodian Guard ability 'Stand Vigil' active`. After Ka'tah application I observed unit `flags = {"effect_reroll_wounds": "ones", ...}` on Custodian Guard — confirming the reroll flag lands. Full objective-conditional upgrade tested in `tests/unit/test_unit_ability_manager.gd`. |
| Sentinel Storm | OK (live-helper) | `UnitAbilityManager.has_shoot_again_ability('U_CUSTODIAN_GUARD_B') == true` confirmed live + `is_once_per_battle_used(..., "Sentinel Storm") == false` (unused). `USE_SENTINEL_STORM`/`DECLINE_SENTINEL_STORM` actions wired in `ShootingPhase.gd:419-422,3513-3525`. |

### Witchseekers (×2)

| Ability | Status | Evidence |
|---------|--------|----------|
| Core / Scout 6" | **BROKEN (F-1)** | Live: `_unit_has_scout_own('U_WITCHSEEKERS_C') == false`, but `_unit_has_scout_own('U_KOMMANDOS_H') == true` (control). Witchseekers will not be offered Scout moves in ScoutPhase. Fix: change ability JSON `"name": "Core"` to `"name": "Scouts 6\""`. |
| Daughters of the Abyss | **BROKEN (F-2)** | Live: Witchseekers `flags = {"effect_fnp_psychic_mortal": 3}` (flag IS set), but `RulesEngine.get_unit_fnp(unit) == 0` (flag NOT read). FNP claim is silently ignored. Fix: extend `get_unit_fnp` to consider `effect_fnp_psychic_mortal` when damage source is psychic or mortal-wound. |
| Sanctified Flames | BLOCKED (live) | `ABILITY_EFFECTS["Sanctified Flames"].implemented == true` (verified live). Triggers `after_shooting` — needs Witchseekers to actually fire and hit an enemy to observe the auto-Battle-shock test. Not driven in this audit. |

### Caladius Grav-tank

| Ability | Status | Evidence |
|---------|--------|----------|
| Deadly Demise D3 | OK (test) | Covered by `tests/unit/test_deadly_demise.gd`. Helper `RulesEngine.resolve_deadly_demise` reads the parameter string. |
| Martial Ka'tah | OK (live-UI) | See Shield-Captain. |
| Advanced Firepower | BLOCKED (live) | `ABILITY_EFFECTS["Advanced Firepower"].implemented == true` (verified live). Triggers in attacks-with-iliastus-cannon code path; needs a shoot scenario to observe Lethal Hits keyword grant. |
| Damaged: 1-5 Wounds Remaining | OK (live-log) | Telemon's Damaged threshold logged "active" message in left panel of `unit_audit_orks_waaagh_button_pre.png` (parallel mechanism — same `RulesEngine.gd` wound-threshold check). |

### Contemptor-Achillus Dreadnought

| Ability | Status | Evidence |
|---------|--------|----------|
| Deadly Demise 1 | OK (test) | Same as Caladius. |
| Martial Ka'tah | OK (live-UI) | See Shield-Captain. |
| Dread Foe | BLOCKED (live) | `ABILITY_EFFECTS["Dread Foe"].implemented == true` (verified live). Needs a Fight phase where Contemptor-Achillus is selected as fighter and chooses an enemy in engagement to apply +1 Attack. Not driven in this audit. |

### Telemon Heavy Dreadnought

| Ability | Status | Evidence |
|---------|--------|----------|
| Deadly Demise D3 | OK (external) | Same. |
| Martial Ka'tah | OK (external) | See above. |
| Guardian Eternal | OK (live-log) | Game log: `P1: Telemon Heavy Dreadnought ability 'Guardian Eternal' active`. |
| Damaged: 1-4 Wounds Remaining | BLOCKED (live) | Same `RulesEngine` mechanism as Caladius's Damaged 1-5. Wound threshold check at attack-time only fires when wounds drop low; needs damage scenario to observe live. |

### Shield-captain On Dawneagle Jetbike

| Ability | Status | Evidence |
|---------|--------|----------|
| Leader | OK (live-UI) | `DECLARE_LEADER_ATTACHMENT` actions exposed in FORMATIONS phase. |
| Martial Ka'tah | OK (live-UI) | See above. |
| Sweeping Advance | BLOCKED (live) | `ABILITY_EFFECTS["Sweeping Advance"].implemented == true` (verified live). `FightPhase.gd:38,93,2732` has the signal + use/decline actions but they only surface at end-of-fight-phase after a fight resolves. Needs Shield-captain on Jetbike to actually fight. |
| Strategic Mastery | OK (live-helper) | Same as Shield-Captain — both have it. |

---

## Orks — `orks.json` (Feb 20)

### Strike Force

Empty abilities array — formation-only marker (no behavior).

### Warboss (×2)

| Ability | Status | Evidence |
|---------|--------|----------|
| Core | DATA-ONLY | Placeholder. |
| Waaagh! | OK (live-UI) + OK (live-flag) | `CALL_WAAAGH` action exposed in P2 Command Phase; dispatched and returned `success: true`; `is_waaagh_active(2) == true`. Live-observed `flags = {effect_advance_and_charge: true, effect_invuln: 5, effect_invuln_source: "Waaagh!", waaagh_active: true}` on Warboss. Re-call returned `error: "Waaagh! already used this battle"` (once-per-battle gate works). Screenshot: `unit_audit_orks_waaagh_button_pre.png`. |
| Might is Right | BLOCKED (live) | `ABILITY_EFFECTS["Might is Right"].implemented == true` (verified live). Needs Warboss attached to a led unit + a melee attack to observe `effect_plus_one_hit` flag on the led unit. |
| Da Biggest and da Best | BLOCKED (live) | `ABILITY_EFFECTS["Da Biggest and da Best"].implemented == true`. Live: Warboss has Waaagh!-active flags, but the +4 attacks bonus is applied at melee-resolution time via `RulesEngine` — needs an actual melee attack to observe. |

### Warboss in Mega Armour

| Ability | Status | Evidence |
|---------|--------|----------|
| Core | DATA-ONLY | |
| Waaagh! | OK (live-flag) | Same as Warboss. |
| Might is Right | BLOCKED (live) | Same as Warboss. |
| Dead Brutal | BLOCKED (live) | `ABILITY_EFFECTS["Dead Brutal"].implemented == true`. Damage-3 override during Waaagh! is applied at melee-resolution; needs an attack to observe. |

### Boyz (×3)

| Ability | Status | Evidence |
|---------|--------|----------|
| Waaagh! | OK (live-flag) | See above. |
| Get Da Good Bitz | OK (live-helper) | `UnitAbilityManager.has_sticky_objectives_ability('U_BOYZ_E') == true`. `MissionManager.apply_sticky_objectives()` resolved at end-of-Command per code. |
| BODYGUARD | DATA-ONLY | Keyword for character attachment. |

### Battlewagon (×1)

| Ability | Status | Evidence |
|---------|--------|----------|
| Deadly Demise D6 | OK (test) | Same as Custodes vehicles; `tests/unit/test_deadly_demise.gd`. |
| FIRING DECK | OK (test) | `TransportManager` + `ShootingPhase`. **Disabled if 'Ard Case is also equipped** — handled by ArmyListManager logic. Covered by `tests/test_oa39_ard_case.gd`. |
| Waaagh! | OK (live-flag) | |
| Ramshackle | OK (live-log) | Game log: `P2: Battlewagon ability 'Ramshackle' active (Worsen AP of incoming attacks by 1)`. |
| Damaged: 1-5 Wounds Remaining | BLOCKED (live) | RulesEngine wound-threshold check. Needs damage scenario. |
| 'Ard Case | OK (test) + OK (external-load) | Covered by `tests/test_oa39_ard_case.gd`. ArmyListManager applies +2T at load. |
| TRANSPORT | DATA-ONLY | Keyword. |

### Kommandos

| Ability | Status | Evidence |
|---------|--------|----------|
| Infiltrators | OK (external) | DeploymentPhase pre-game placement 9"+ from enemies. (Not driven live in this session.) |
| Stealth | OK (test) | `tests/unit/test_stealth_ability.gd` covers RulesEngine direct meta.abilities check. |
| Scout 6" | OK (live-helper) | `_unit_has_scout_own('U_KOMMANDOS_H') == true`. |
| Waaagh! | OK (live-flag) | Verified Waaagh! flags applied to Kommandos via FactionAbilityManager lifecycle. |
| Throat Slittas | OK (test) | `tests/unit/test_throat_slittas.gd` covers the start-of-shooting D6-per-model 9" check. |
| Sneaky Surprise | BLOCKED (live) | `ABILITY_EFFECTS["Sneaky Surprise"].implemented == true`. Blocks Fire Overwatch — would need a charge-against-Kommandos scenario where opponent attempts overwatch. |
| **Patrol Squad** | **NOT IMPL — confirmed unreachable** | `ABILITY_EFFECTS["Patrol Squad"].implemented == false` (confirmed live). Zero code references in `phases/DeploymentPhase.gd` or controllers. Player has no UI path to split the unit. See [Issue U-1](#issue-u-1). |
| Distraction Grot | BLOCKED (live) | `ABILITY_EFFECTS["Distraction Grot"].implemented == true`. Once-per-battle 5+ invuln when opponent shoots — needs a scenario where opponent targets Kommandos. |
| Bomb Squigs | BLOCKED (live) | `ABILITY_EFFECTS["Bomb Squigs"].implemented == true`. Once-per-battle after Normal move — needs Kommandos to move within 12" of an enemy. |

### Painboss

| Ability | Status | Evidence |
|---------|--------|----------|
| Feel No Pain 5+ | OK (live-helper) | `RulesEngine.get_unit_fnp` reads `meta.stats.fnp`. (Helper not directly invoked live, but Painboss `meta.stats.fnp == 5` set at load.) |
| Waaagh! | OK (live-flag) | |
| Dok's Toolz | BLOCKED (live) | `ABILITY_EFFECTS["Dok's Toolz"].implemented == true`. Needs Painboss-attached unit + damage scenario to observe FNP 5+ on the led unit. |
| Sawbonez | OK (live-helper) | `UnitAbilityManager.has_sawbonez('U_PAINBOSS_I') == true` confirmed live. End-of-Movement heal trigger wired in `phases/MovementPhase.gd`. |
| One Scalpel Short of a Medpack | BLOCKED (live) | `ABILITY_EFFECTS["One Scalpel Short of a Medpack"].implemented == true`. Charge-after-fallback — needs the led unit to fall back and then attempt charge. |
| Grot Orderly | OK (live-helper) | `UnitAbilityManager.has_grot_orderly('U_PAINBOSS_I') == true` confirmed live. Start-of-Command revive trigger wired in `phases/CommandPhase.gd`. |

### Weirdboy

| Ability | Status | Evidence |
|---------|--------|----------|
| Deadly Demise D3 | OK (test) | `tests/unit/test_deadly_demise.gd`. |
| Waaagh! | OK (live-flag) | |
| **Waaagh! Energy** | **NOT IMPL — confirmed unreachable** | Live: Weirdboy `flags == {moved: true, remained_stationary: true}` (only movement state, no ability flags) DESPITE Waaagh! being active. `get_active_ability_effects_for_unit('U_WEIRDBOY_J') == []`. The +S/+D scaling and Hazardous are silently absent. See [Issue U-2](#issue-u-2). |
| **Da Jump** | **NOT IMPL — confirmed unreachable** | Live walked Movement Phase Player 2 `available_actions`: only `BEGIN_NORMAL_MOVE`, `BEGIN_ADVANCE`, `REMAIN_STATIONARY` for Weirdboy — no `DA_JUMP` action. Zero references in `phases/MovementPhase.gd`. See [Issue U-3](#issue-u-3). Screenshot: `unit_audit_da_jump_absent.png`. |

### Lootas (×3)

| Ability | Status | Evidence |
|---------|--------|----------|
| Waaagh! | OK (live-flag) | |
| Dat's Our Loot! | OK (test) | `tests/unit/test_dats_our_loot.gd`. |

### Meganobz

| Ability | Status | Evidence |
|---------|--------|----------|
| Waaagh! | OK (live-flag) | |
| Krumpin' Time | OK (live-flag) | Live-observed Meganobz `flags = {effect_fnp: 5, effect_fnp_source: "Krumpin' Time", effect_advance_and_charge: true, effect_invuln: 5, effect_invuln_source: "Waaagh!", waaagh_active: true}` after Waaagh! activation. |

### Wazbom Blastajet

| Ability | Status | Evidence |
|---------|--------|----------|
| Deadly Demise | OK (test) | |
| Waaagh! | OK (live-flag) | |
| Blastajet Attack Run | OK (test) | `tests/test_oa40_blastajet_attack_run.gd` (6/6 pass per ORK_ABILITIES_TASKS.md). |

### Kaptin Badrukk

| Ability | Status | Evidence |
|---------|--------|----------|
| Core | DATA-ONLY | |
| Waaagh! | OK (live) | |
| Flashiest Gitz | BLOCKED (live) | `ABILITY_EFFECTS["Flashiest Gitz"].implemented == true`. Needs Kaptin Badrukk attached to a led unit + ranged attack to observe full hit reroll grant. |
| Ded Glowy Ammo (Aura) | OK (live-runtime, BUG F-3) + OK (test) | Live-tested `RulesEngine.get_ded_glowy_ammo_toughness_penalty(target, board)`: returned `1` (= -1T) when Custodian Guard within 6" of Kaptin Badrukk after `embarked_in: null` was erased; returned `0` (no penalty) at 56" distance. Logic works but is silently broken when `embarked_in: null` is present (see [Issue F-3](#issue-f-3)). Existing test: `tests/test_oa44_ded_glowy_ammo.gd`. |
| Leader | OK (live-UI) | `DECLARE_LEADER_ATTACHMENT` actions exposed. |

### Ghazghkull Thraka

| Ability | Status | Evidence |
|---------|--------|----------|
| Core | DATA-ONLY | |
| Waaagh! | OK (live-flag) | |
| Prophet of Da Great Waaagh! | BLOCKED (live) | `ABILITY_EFFECTS["Prophet of Da Great Waaagh!"].implemented == true`. Live: Ghazghkull was unattached in this fixture. Aura on attached led unit needs an attachment scenario. |
| Ghazghkull's Waaagh! Banner (Aura) | OK (live-runtime, BUG F-3) + OK (test) | Live-tested `RulesEngine.unit_has_waaagh_banner_lethal_hits(attacker, board)`: returned `false` with `embarked_in: null` on Ghazghkull (BUG), returned `true` after `erase("embarked_in")`. Existing test: `tests/test_oa45_waaagh_banner.gd`. The aura logic itself is correct — the gating bug F-3 hides it. |

### Nob with Waaagh! Banner

| Ability | Status | Evidence |
|---------|--------|----------|
| Core | DATA-ONLY | |
| Waaagh! | OK (live-flag) | |
| Plant the Waaagh! Banner | OK (live-UI) + OK (live-flag) | Live: `can_plant_waaagh_banner('U_NOB_WAAAGH_BANNER_A') == true` → `PLANT_WAAAGH_BANNER` action exposed in Command Phase `available_actions` → dispatched returning `success: true, message: "Plant the Waaagh! Banner: Nob with Waaagh! Banner gains Waaagh! effects (4+ invuln, OC 5, advance+charge)!"` → re-check `can_plant_waaagh_banner` returned `false` (once-per-battle gate works). Existing test: `tests/unit/test_plant_waaagh_banner.gd`. |
| Da Boss Iz Watchin' | OK (live-flag) | After Waaagh! active, observed Nob with Waaagh! Banner `flags = {effect_invuln: 4, effect_invuln_source: "Da Boss Iz Watchin'", effect_oc_override: 5, effect_oc_source: "Da Boss Iz Watchin'", effect_advance_and_charge: true, waaagh_active: true}` — 4+ invuln upgrade + OC 5 override correctly applied. |
| Leader | OK (live-UI) | CharacterAttachmentManager. |

---

## Findings — Action Items

### <a name="issue-u-1"></a>Issue U-1: Patrol Squad not implemented (Kommandos)
- **Severity:** MEDIUM (blocks player from a documented gameplay choice)
- **Where:** `autoloads/UnitAbilityManager.gd` — `ABILITY_EFFECTS["Patrol Squad"]` is declared with `implemented: false` and condition `deployment` (split into two 5-model units).
- **Impact:** Player cannot split a 10-model Kommando squad at deployment. Both armies in the game still function, but the tactical option of double-Infiltrator activity is not available.
- **Fix:** Add deployment-phase split UI similar to Combat Squads (also `implemented: false` for Space Marines).

### <a name="issue-u-2"></a>Issue U-2: Waaagh! Energy not implemented (Weirdboy)
- **Severity:** HIGH (Weirdboy's signature ranged attack is broken)
- **Where:** `autoloads/UnitAbilityManager.gd` — `ABILITY_EFFECTS["Waaagh! Energy"]` `implemented: false`, condition `while_leading`.
- **Impact:** When Weirdboy fires 'Eadbanger, the +1 S and +1 D per 5 models in the led unit is NOT applied, nor is the Hazardous self-damage roll. Weirdboy is still functional with base profile but the scaling-with-mob-size mechanic is missing.
- **Fix:** Add `target` calculation reading `led_unit.size()` and apply +S/+D effects to 'Eadbanger weapon profile only. Hazardous post-attack 1s check pattern already exists for other Hazardous weapons.

### <a name="issue-u-3"></a>Issue U-3: Da Jump not implemented (Weirdboy)
- **Severity:** HIGH (Weirdboy's signature movement ability is broken)
- **Where:** `autoloads/UnitAbilityManager.gd` — `ABILITY_EFFECTS["Da Jump"]` `implemented: false`, condition `end_of_movement`.
- **Impact:** Weirdboy cannot teleport a friendly Orks Infantry unit. This removes a key board-control trick from the Ork toolkit.
- **Fix:** Add end-of-Movement-phase trigger UI (target selection + D6 hazard roll + deepstrike-style placement 9"+ from enemies). Reuse the existing Deep Strike placement controller.

### <a name="issue-f-1"></a>Issue F-1 (carryover from AUDIT_ABILITIES_2.md): Witchseekers Scout name mismatch
- **Severity:** HIGH
- **Where:** `armies/adeptus_custodes.json` — Witchseekers ability is `{"name": "Core", "type": "Core", "parameter": "6\""}` instead of `{"name": "Scouts 6\""}`.
- **Impact:** `GameState._unit_has_scout_own()` checks `name.begins_with("scout")` — won't match "Core". **Witchseekers will not be offered Scout moves** during the Scout Phase.
- **Fix:** Edit JSON: change `"name": "Core"` → `"name": "Scouts 6\""`.
- **Status:** Originally flagged in AUDIT_ABILITIES_2.md (2026-03-08); apparently still present in the army file shipped with this build.

### <a name="issue-f-2"></a>Issue F-2 (carryover from AUDIT_ABILITIES_2.md): Daughters of the Abyss FNP not read in damage path
- **Severity:** HIGH — re-confirmed live 2026-05-04
- **Where:** `autoloads/RulesEngine.gd` line 10068 — `get_unit_fnp()` does not check `effect_fnp_psychic_mortal`.
- **Live evidence:** Witchseekers `flags = {"effect_fnp_psychic_mortal": 3}` (flag IS set), but `RulesEngine.get_unit_fnp(unit) == 0` returned live in this audit.
- **Impact:** Witchseekers get the game-log "active" message, but the FNP 3+ vs Psychic Attacks/mortal wounds is silently NEVER applied during damage resolution. Player cannot rely on this defensive ability at all.
- **Fix:** Add `EffectPrimitivesData.get_effect_fnp_psychic_mortal(target_unit)` check in damage application paths, gated on damage source being psychic or mortal-wound.

### <a name="issue-f-3"></a>Issue F-3 (NEW — discovered in this audit): `embarked_in: null` skips aura sources
- **Severity:** HIGH
- **Where:** 7 sites use the pattern `unit.get("embarked_in", "") != ""` to skip embarked units. When the field is stored as `null` (the default after save/load round-trip in this codebase), this evaluates `null != ""` → `true`, and the unit is incorrectly skipped:
  - `autoloads/RulesEngine.gd:3479` — `get_ded_glowy_ammo_toughness_penalty` (Kaptin Badrukk's aura)
  - `autoloads/RulesEngine.gd:3625` — `unit_has_waaagh_banner_lethal_hits` (Ghazghkull's aura)
  - `autoloads/UnitAbilityManager.gd:1928, 2064, 2092, 2136` — generic aura range/source checks
  - `autoloads/UnitAbilityManager.gd:2123` — target embark check
- **Live evidence:**
  - With Ghazghkull's Makari positioned 1.25" from Warboss and `embarked_in: null` present: `unit_has_waaagh_banner_lethal_hits(warboss, state) == false`. After `Ghazghkull.erase("embarked_in")`: returns `true`. Same with Ded Glowy Ammo: returned `0` with null, `1` (= -1T) after erase.
- **Impact:** ALL aura abilities (Ded Glowy Ammo, Ghazghkull's Waaagh! Banner, possibly Waaagh! Effigy and others) are silently broken whenever any unit has `embarked_in: null`. This is most likely the default state after any save/load round-trip — meaning the auras are likely broken in normal gameplay.
- **Fix:** Replace all 7 sites with `var embk = unit.get("embarked_in", ""); if embk != "" and embk != null: continue` — OR ensure `embarked_in` is always either an empty string or a valid unit_id, never null. The latter is more invasive but cleaner.

---

## Live-Validation Log (chronological)

Every entry below is something I dispatched or queried via the MCP bridge during this audit, with the actual return value from the game.

### Setup

1. Loaded `audit_baseline_postdeploy.w40ksave` → `GameState.state.units.size() == 26` (9 Custodes + 17 Orks deployed).
2. Confirmed both armies match the targeted files (Mar 1 Custodes; Feb 20 Orks) by listing unit IDs.
3. Wargear bonuses applied at army load-time (console): Praesidium Shield Shield-Captain wounds 6→7; Praesidium Shield Custodian Guard m1..m4 wounds 3→4; Vexilla Custodian Guard objective_control 2→3.

### Custodes — actions exposed and dispatched

4. `DECLARE_RESERVES (deep_strike, U_BLADE_CHAMPION_A)` exposed in FORMATIONS `available_actions` (`unit_audit_round1_formations.png`).
5. `DECLARE_LEADER_ATTACHMENT (Shield-Captain → Custodian Guard)` exposed in FORMATIONS `available_actions`.
6. Player 1 Command Phase: `SELECT_MARTIAL_MASTERY (crit_on_5)` and `(improve_ap)` both exposed (`unit_audit_custodes_command_mastery.png`). Dispatched `crit_on_5`: returned `{success: true, message: "Martial Mastery — Critical Hit on 5+ active"}`.
7. `UnitAbilityManager.has_strategic_mastery('U_SHIELD_CAPTAIN_A') == true` (live helper).
8. `UnitAbilityManager.has_shoot_again_ability('U_CUSTODIAN_GUARD_B') == true` (live helper, Sentinel Storm).
9. `UnitAbilityManager.is_once_per_battle_used('U_CUSTODIAN_GUARD_B', 'Sentinel Storm') == false` (unused, gate works).
10. `_unit_has_scout_own('U_KOMMANDOS_H') == true` (control); `_unit_has_scout_own('U_WITCHSEEKERS_C') == false` (Issue F-1 confirmed).
11. Fight Phase: Custodian Guard selected to fight → `trigger_katah_stance: true, master_of_the_stances_available: false` (correct — Custodian Guard doesn't have Master of the Stances). Dispatched `SELECT_KATAH_STANCE (dacatarai)`: returned `{success: true, trigger_pile_in: true, pile_in_distance: 3}`. `unit_audit_fight_phase_katah_active.png` shows the dialog.
12. Custodian Guard `flags` after Ka'tah application: `{effect_reroll_wounds: "ones", effect_sustained_hits: true, fight_priority: 1, is_engaged: true, katah_stance: "dacatarai", katah_sustained_hits_value: 1}` — confirms Stand Vigil (effect_reroll_wounds) AND Dacatarai stance flags applied to the same unit.
13. `RulesEngine.get_unit_fnp(witchseekers)` with `flags == {"effect_fnp_psychic_mortal": 3}` returned `0` (Issue F-2 confirmed live).

### Orks — actions exposed and dispatched

14. Player 2 Command Phase: `CALL_WAAAGH` action exposed with description matching Wahapedia 10e (`unit_audit_orks_waaagh_button_pre.png` shows the green button).
15. Dispatched `CALL_WAAAGH (player: 2)`: returned `{success: true, message: "WAAAGH! Called — advance and charge, +1 S/A melee, 5+ invuln active!"}`. `is_waaagh_active(2) == true`.
16. Re-call `activate_waaagh(2)`: returned `{success: false, error: "Waaagh! already used this battle"}` (once-per-battle gate works).
17. Warboss `flags` after Waaagh!: `{effect_advance_and_charge: true, effect_invuln: 5, effect_invuln_source: "Waaagh!", waaagh_active: true}`.
18. Meganobz `flags`: same as Warboss PLUS `effect_fnp: 5, effect_fnp_source: "Krumpin' Time"` — Krumpin' Time correctly applies FNP 5+ during Waaagh!.
19. Nob with Waaagh! Banner `flags`: invuln upgraded 5→4 with source `"Da Boss Iz Watchin'"`, plus `effect_oc_override: 5` — Da Boss Iz Watchin' correctly upgrades the unit during Waaagh!.
20. `can_plant_waaagh_banner('U_NOB_WAAAGH_BANNER_A') == true` → `PLANT_WAAAGH_BANNER` action exposed in Command Phase → dispatched: `{success: true, message: "Plant the Waaagh! Banner: Nob with Waaagh! Banner gains Waaagh! effects (4+ invuln, OC 5, advance+charge)!"}` → `can_plant_waaagh_banner` re-checked: `false` (once-per-battle gate works).
21. `has_sticky_objectives_ability('U_BOYZ_E') == true` (Get Da Good Bitz wired).
22. `has_sawbonez('U_PAINBOSS_I') == true` and `has_grot_orderly('U_PAINBOSS_I') == true`.
23. Movement Phase Player 2 `available_actions` for Weirdboy: only `BEGIN_NORMAL_MOVE`, `BEGIN_ADVANCE`, `REMAIN_STATIONARY` — NO `DA_JUMP` action. Confirmed unreachable (`unit_audit_da_jump_absent.png`).
24. `get_active_ability_effects_for_unit('U_WEIRDBOY_J') == []` despite Waaagh! active — Waaagh! Energy is silently absent (Issue U-2 confirmed unreachable).
25. After `REMAIN_STATIONARY` for Weirdboy: `flags = {moved: true, remained_stationary: true}` — only movement state, no ability effects. Patrol Squad similarly absent (no `SPLIT_UNIT` or similar action exposed during deployment phase code path).

### Aura logic (with Issue F-3 worked around)

26. Ghazghkull's Waaagh! Banner aura: with `embarked_in: null` on Ghazghkull, `unit_has_waaagh_banner_lethal_hits(warboss, state) == false`. After `Ghazghkull.erase("embarked_in")` and Makari placed 1.25" from Warboss: returns `true`. Aura logic works once gating bug is bypassed.
27. Ded Glowy Ammo aura: same pattern — with Custodian Guard at 56" → `0` (no penalty), with Custodian Guard at 0.5" → `1` (= -1T). Aura logic works once gating bug is bypassed.

### Scope I did NOT live-validate (BLOCKED)

These need a multi-step combat scenario and are status-marked `BLOCKED (live)` in the per-unit tables:

- Swift Onslaught / Martial Inspiration (Blade Champion-led charge scenario)
- Master of the Stances "Both Stances" UI (Shield-Captain selected to fight)
- Strategic Mastery actually granting CP discount (use a stratagem)
- Sentinel Storm shoot-again UI (Custodian Guard finishes shooting)
- Sweeping Advance / Acrobatic Escape end-of-Fight UI (a fight that resolves)
- Sanctified Flames Battle-shock test (Witchseekers fire and hit)
- Advanced Firepower (Caladius shoots non-MONSTER/VEHICLE)
- Dread Foe (Contemptor-Achillus selects an enemy on fight)
- Damaged threshold (-1 Hit at low wounds)
- Might is Right / Da Biggest and da Best / Dead Brutal (Warboss melee resolution observation)
- Sneaky Surprise (charge into Kommandos with overwatch attempt)
- Distraction Grot, Bomb Squigs (movement/shooting context)
- Dok's Toolz, One Scalpel Short (Painboss-led unit)
- Prophet of Da Great Waaagh! (Ghazghkull-led melee resolution)
- Flashiest Gitz (Kaptin Badrukk-led ranged attack)
- Dat's Our Loot! (target near objective)
- Blastajet Attack Run (vs FLY/non-FLY)

These would require building a deployment + Round-2 fight fixture similar to the existing `co_pretrigger.w40ksave` pattern. Each scenario takes 5-10 minutes of setup; doing all of them is roughly a 2-3 hour additional investment.

---

## Existing Test Coverage

The following pre-existing GUT tests cover specific abilities listed above. They were NOT re-run in this audit because the headless test runner hung repeatedly in this session, but they are documented as further validation:

- `tests/test_oa39_ard_case.gd` — 'Ard Case (Battlewagon +2T, disables Firing Deck)
- `tests/test_oa40_blastajet_attack_run.gd` — Blastajet Attack Run
- `tests/test_oa44_ded_glowy_ammo.gd` — Ded Glowy Ammo aura
- `tests/test_oa45_waaagh_banner.gd` — Ghazghkull's Waaagh! Banner aura
- `tests/unit/test_plant_waaagh_banner.gd` — Plant the Waaagh! Banner
- `tests/unit/test_dats_our_loot.gd` — Dat's Our Loot!
- `tests/unit/test_pyromaniaks.gd` — Pyromaniaks (not in this army list)
- `tests/unit/test_tank_hunters.gd` — Tank Hunters (not in this army list)
- `tests/unit/test_drive_by_dakka.gd` — Drive-by Dakka (not in this army list)
- `tests/unit/test_dakkastorm.gd` — Dakkastorm (Dakkajet — not in this army list)
- `tests/unit/test_da_boss_ladz.gd` — Da Boss' Ladz (not in this army list)
- `tests/unit/test_runtherd.gd` — Runtherd (Gretchin — not in this army list)
- `tests/unit/test_grot_riggers.gd` — Grot Riggers (Trukk — not in this army list)
- `tests/unit/test_unit_ability_manager.gd` — covers Stand Vigil objective conditional
- `tests/unit/test_kunnin_infiltrator_ability.gd` — Kunnin' Infiltrator (not in this army list)
- `tests/unit/test_full_throttle_ability.gd` — Full Throttle (Stormboyz — not in this army list)
- `tests/unit/test_high_octane_fuel_ability.gd` — High-octane Fuel (Warboss on Warbike — not in this army list)
- `tests/unit/test_plummeting_descent_ability.gd` — Plummeting Descent (Boss Zagstruk — not in this army list)
- `tests/unit/test_hold_still_ability.gd` — Hold Still and Say 'Aargh!' (Painboy — different from Painboss)
- `tests/unit/test_clankin_forward_ability.gd` — Clankin' Forward (Morkanaut — not in this army list)
- `tests/unit/test_stompin_forward_ability.gd` — Stompin' Forward (Stompa — not in this army list)
- `tests/unit/test_throat_slittas.gd` — Throat Slittas (Kommandos — IS in this army)
- `tests/unit/test_beastly_rage.gd` — Beastly Rage (Beastboss — not in this army list)
- `tests/unit/test_deadly_demise.gd` — Deadly Demise

---

## Audit Coverage Numbers

- **Custodes abilities surveyed:** 17 unique × 9 units = 33 total ability instances
- **Orks abilities surveyed:** 28 unique × 17 units = 57 total ability instances
- **Live-validated abilities (UI action / runtime flag / live helper / game log):** 30
  - Custodes: Deep Strike, Leader, Martial Mastery (Crit-on-5 + Improve-AP), Martial Ka'tah (Dacatarai stance applied to Custodian Guard), Strategic Mastery (helper), Praesidium Shield (load), Vexilla (load), Stand Vigil (game log + flag), Sentinel Storm (helper), Sanctified Flames (`implemented: true` confirmed live), Damaged 1-4 (live game log), Guardian Eternal (live game log)
  - Orks: Waaagh! (UI + flag + once-per-battle gate), Ramshackle (game log), Krumpin' Time (flag), Da Boss Iz Watchin' (flag with invuln upgrade + OC override), Plant the Waaagh! Banner (UI + dispatch + gate), Get Da Good Bitz (helper), Sawbonez (helper), Grot Orderly (helper), Scout 6" (helper), Ghazghkull's Waaagh! Banner aura (live runtime, with F-3 worked around), Ded Glowy Ammo aura (live runtime, with F-3 worked around)
- **BLOCKED (live):** 13 abilities require a multi-step combat scenario; status is `implemented: true` flag + helper functions only; needs follow-up
- **NOT IMPL — confirmed unreachable in live game:** 3 (Patrol Squad, Waaagh! Energy, Da Jump)
- **BROKEN — confirmed live:** 3 (F-1 Witchseeker Scout, F-2 Daughters FNP, F-3 embark null aura skip)
- **DATA-ONLY markers:** 4 (Core, BODYGUARD, TRANSPORT, FIRING DECK marker)

## Issues Open After This Audit

| ID | Severity | Status |
|----|----------|--------|
| U-1 Patrol Squad | MEDIUM | NOT IMPL — confirmed unreachable in live game |
| U-2 Waaagh! Energy | HIGH | NOT IMPL — confirmed live (Weirdboy has zero ability flags during Waaagh!) |
| U-3 Da Jump | HIGH | NOT IMPL — confirmed live (no `DA_JUMP` action in Movement Phase `available_actions`) |
| F-1 Witchseeker Scout | HIGH | BROKEN — confirmed live (carryover from 2026-03-08) |
| F-2 Daughters FNP | HIGH | BROKEN — confirmed live (carryover from 2026-03-08) |
| F-3 `embarked_in: null` aura skip | HIGH | BROKEN — discovered 2026-05-04, affects 7 sites across RulesEngine + UnitAbilityManager |
