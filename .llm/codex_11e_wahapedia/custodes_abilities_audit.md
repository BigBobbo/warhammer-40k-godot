# Codex: Adeptus Custodes (11e) — datasheet + wargear ability audit (WP-C7)

Source: `custodes/wahapedia/Datasheets_abilities.csv` (type Datasheet /
Wargear) joined with `Datasheets.csv`. 45 distinct names on 36 datasheets:
the 29 in-scope datasheets carry **36 abilities + Master of Ka'tahs** (WP-C3);
the other 9 names (and two variant texts) are only on the 7 Legends datasheets
the import skipped (import_report_custodes.md) — listed at the end, not
implemented.

"Before" = the game at the WP-C7 base (dc5f3aa1): the 10e / 1.0.19
`ABILITY_EFFECTS` rows and pipelines. Code: `40k/scripts/codex/custodes/CustodesAbilities.gd`
(thin hooks elsewhere). Tests: `40k/tests/test_custodes_abilities_11e.gd`
(section numbers below); windowed scenarios `40k/tests/scenarios/sp/cus11e_ab_*.json`.

Usage limits printed in parentheses are enforced: once per battle per unit
via the UnitAbilityManager ledger (`mark_once_per_battle_used` /
`is_once_per_battle_used`, the key GILDED CHAMPION restores); once per battle
per army (Moment Shackle) via the `moment_shackle_used` flag GILDED CHAMPION
already reads; once per phase via a per-unit / per-army phase key.

| datasheet | ability | printed text (short) | game status before | action |
|---|---|---|---|---|
| Trajann Valoris | Captain-General (Aura) | friendly CUSTODES (not MONSTER/VEHICLE) within 6": re-roll hit 1s and wound 1s | 10e: "while leading, ignore hit modifiers" (RulesEngine `has_captain_general`) | rewritten: aura in `attack_mods` (all resolver paths via the WP-O6 aggregator); 10e helper deleted. §1, scenario `cus11e_ab_captain_general` |
| Trajann Valoris | Moment Shackle (once per battle, per army) | start of any phase: Watcher's Axe +3 A, or this model 3+ InSv, until end of phase | 10e: Fight-phase-start prompt (MomentShackleDialog: 12 A / 2+ InSv) | rewritten: two-variant card in the new start-of-phase window (`phase_start`, BasePhase); phase-scoped flag; 3+ InSv on Trajann incl. his attached-unit allocation copy; once per army (`moment_shackle_used`); dialog + FightPhase queue deleted; AI scores it. §2, scenarios `cus11e_ab_moment_shackle`, `ai_moment_shackle_window`, `cus11e_gilded_champion` |
| Trajann Valoris | SUPREME COMMANDER | must be your WARLORD | not enforced | FormationsPhase warlord check matches the folded name. §3|
| Shield-Captain | Vengeful Surge (once per battle, per unit) | opponent's Shooting phase, enemy has shot, a model lost a wound: surge move up to D6+2" | none | `enemy_has_shot` window card → ShootingPhase surge-move follow-up (D6+2"); not when engaged or battle-shocked. §4, scenario `cus11e_ab_vengeful_surge` |
| Shield-Captain | Praesidium Shield (Wargear) | attacks allocated to this model have -1 D | 10e +1 W (already removed by the import); no -1 D | -1 D (min 1) in the 11e allocation damage provider (every interactive / auto / overwatch path) incl. the Shield-Captain's copy inside an Attached unit (`cus11e_src_unit_id` tag); a dice-log line "Praesidium Shield: -1 Damage (a -> b)". §5, scenario `cus11e_ab_praesidium_shield` |
| Sentinel Guard Sodality | Praesidium Shield (Wargear) | attacks with S > this unit's T have -1 to wound | none | incoming wound penalty hook (shared with Unyielding Ancient). §5|
| Shield-Captain in Allarus Terminator Armour | Archeotech Teleport-shunter (once per battle, per unit) | your Movement phase, unengaged, not selected to move: strategic reserves + must make an ingress move this phase | none | `movement_phase_start` window card (round ≥ 2); the Attached unit goes to strategic reserves; END_MOVEMENT refused until it has arrived. §6, scenario `cus11e_ab_archeotech_teleport_shunter` |
| Shield-Captain on Dawneagle Jetbike | Sweeping Advance (once per battle, per unit) | end of Fight phase, if eligible to fight: normal move (unengaged) or fall-back (engaged) | 10e-shaped: only units that fought | eligibility = fought, engaged now, or engaged/charged at the start of the Fight phase (stamp); existing SweepingAdvanceDialog + ledger. §7, scenario `cus11e_ab_sweeping_advance` |
| Custodian Wardens | Living Fortress | attacks that target this unit have -1 AP | none | EffectPrimitives worsen-AP getter. §8|
| Wardens, Allarus, Custodian Guard, Sentinel Guard | Vexilla (Wargear) | +1 OC; can ignore modifiers to this unit's Ld | +1 OC at army load (ArmyListManager) | + battle-shock / Ld tests ignore Ld modifiers for the unit (CommandPhase). §8|
| Allarus Custodians | Slayer of Tyrants | melee attacks vs a unit with higher T: +1 to wound | none (10e "Slayers of Tyrants" re-roll pipeline existed under the plural name) | `attack_mods` (T read per 19.02 for Attached units). §9|
| Vertus Praetors | Quicksilver Execution | charged this turn: melee [SUSTAINED HITS 1] | 10e: fly-over mortal wounds after a move (MovementPhase) | 10e pipeline deleted; sustained hits in `attack_mods` (melee consumer added). §10|
| Contemptor-Achillus / -Galatus | Unyielding Ancient | attacks with S > this unit's T: -1 to wound | none | incoming wound penalty hook. §11|
| Caladius Grav-Tank | Destructor Optics | ranged attacks vs non-MONSTER/VEHICLE: +1 AP | none | `attack_mods` AP. §12, scenario `cus11e_ab_destructor_optics` |
| Coronus Grav-Carrier | Repulsor Suspensor Technology (once per phase, per unit) | opponent's Shooting phase, lost a wound, unengaged: normal move up to D6" | none | `enemy_has_shot` window card → reactive normal-move follow-up. §13, scenario `cus11e_ab_repulsor_suspensor_technology` |
| Coronus Grav-Carrier, Anathema Psykana Rhino | Assault Vehicle | after an advance move: embarked units can make a shock disembark move | none | **NOT implemented**: the local 11e core rules define no shock disembark move; row says so (`implemented: false`). §14|
| Telemon Heavy Dreadnought | Guardian Eternal | ranged attacks that target this unit: -1 D | 10e row: -1 D on every attack | ranged only (EffectPrimitives damage-minus via `defence_mods`). §15|
| Pallas Grav-Attack | Mobile Hunter | your Shooting phase, has shot: normal move up to D6"; no charge this turn | none | `unit_has_shot` window card → reactive normal move + charge lock (ChargePhase, RulesEngine.eligible_to_charge, ChargeMove11e). §16, scenario `cus11e_ab_mobile_hunter` |
| Orion Assault Dropship | Assault Dropship | tactical disembark from it, then advance: still eligible to charge | none | disembark hook flag → advance-and-charge. §17|
| Ares Gunship | Infernus Firebombs | end of opponent's Fight phase: visible non-Lone-Operative non-AIRCRAFT enemy within 24": [IGNORES COVER] vs it until end of your next turn; D6 per model, 6 = 1 MW (max 6) | none | `fight_phase_end` window card (one per unit per phase); flag + MW. §18, scenario `cus11e_ab_infernus_firebombs` |
| Blade Champion | Swift Onslaught | re-roll advance rolls and charge rolls | 10e row: re-roll charge for the led unit | advance + charge re-roll sources (whole Attached unit). §19|
| Blade Champion | Sword of the Throne | start of the first battle round: pick an enemy unit as mark; +1 to wound vs it; re-pick when it is destroyed | none | `phase_start` window card with an enemy picker (round 1, and after the mark dies); +1 to wound in `attack_mods` (this model only). §20, scenario `cus11e_ab_sword_of_the_throne` |
| Knight-Centura | Seeker's Instincts | +2" M; re-roll advance and charge rolls | none | move modifier + re-roll sources. §19|
| Knight-Centura | Corner the Quarry | an engaged enemy (not MONSTER/VEHICLE) falling back must use desperate escape; -1 to those hazard rolls if battle-shocked | none | MovementPhase / FallBackMove hooks. §21|
| Custodian Guard Sodality | Impenetrable Defence | [SUSTAINED HITS 1: non-MONSTER/VEHICLE] if this unit or the target is within range of an objective | none | `attack_mods`. §22|
| Prosecutor Squad | Purity of Execution | your Shooting phase: a visible enemy within 18" is detected (+3" detection range) | 10e: [PRECISION]+[DEVASTATING WOUNDS] vs PSYKER | 10e rule deleted; `unit_selected_to_shoot` window card (once per phase per unit); detection-range bonus read by TerrainManager. §23, scenario `cus11e_ab_purity_of_execution` |
| Venatari (both) | Take Wing | end of opponent's Fight phase, unengaged: strategic reserves | none | `fight_phase_end` window card. §24, scenario `cus11e_ab_take_wing` |
| Venatari (both) | Neutronium Cascade Mine (once per battle, per unit) | start of any phase: enemy within 3", D6 2+: D3 MW (2D3 vs VEHICLE/MONSTER) | none | `phase_start` window card with picker; mortal wounds (bodyguard first). §25, scenario `cus11e_ab_neutronium_cascade_mine` |
| Venatari with Verutum Lances | Swift Ruin (once per phase, per army) | Rapid Ingress on this unit regardless of other uses this phase; -1 CP; does not block other uses | none | StratagemManager: -1 CP + once-per-phase exemption (shared path with WP-C46 Leonine Ferocity); the Rapid Ingress offer is target-aware and its dialog shows the unit's own cost. §26, scenario `cus11e_ab_swift_ruin` |
| Aquilon Terminators (Gauntlets) | Dread Foe | melee vs non-MONSTER/VEHICLE: +1 AP | 10e: mortal-wound roll when selected to fight | 10e deleted; `attack_mods` AP. §27|
| Sentinel Guard Sodality | Stand Vigil | [LETHAL HITS: non-MONSTER/VEHICLE] if this unit or the target is within range of an objective | 10e row (Adrasite text): re-roll wounds | rewritten (Sentinel Guard text; the Adrasite version is Legends). §22|
| Witchseeker Squad | Sanctified Flames | your Shooting phase, has shot: an enemy unit hit makes a battle-shock roll (-1 if PSYKER) | 10e: automatic test after every shot | 10e auto test deleted; `unit_has_shot` window card with a picker (one use per shot). §28, scenario `cus11e_ab_sanctified_flames` |
| Gyrfalcon Jetbike Sodality | Death Blow | charged this turn: melee +1 AP | none | `attack_mods`. §27|
| Vigilator Squad | Deft Parry | melee attacks that target this unit: -1 to hit | none | `attack_mods` (target side, any attacker). §29, scenario `cus11e_ab_deft_parry` |
| Aquilon Terminators (Talons) | Reap a Terrible Tally | vs INFANTRY: re-roll hit 1s and wound 1s | none | `attack_mods`. §29|
| Caladius Annihilator | Advanced Firepower | ranged vs MONSTER/VEHICLE: re-roll one hit, one wound and one damage roll | 10e: per-weapon [LETHAL HITS] | 10e rule deleted; **codex rule NOT implemented** (single-die re-rolls; WP-C46's Magna Imperator plumbing could host it) — row `implemented: false`. §31|
| Venatari with Kinetic Destroyers | Strike from the Skies | your Shooting phase, made an ingress move this turn: re-roll hit rolls | none | `attack_mods` (arrival stamp). §30|
| Shield-Captain (3 variants) | Master of Ka'tahs | — | — | WP-C3 (out of scope) |

## Deleted 10e dispatch (no codex datasheet has these rules)

| rule | what was removed | tests |
|---|---|---|
| Martial Inspiration | ABILITY_EFFECTS row (advance-and-charge) | none left |
| Devoted to Destruction | ABILITY_EFFECTS row (+2 A) | `test_fullauto_faction_rules.gd` section retired (RETIRED_TESTS.md) |
| Strategic Mastery | row + StratagemManager CP discount | — |
| Slayers of Tyrants | row + RulesEngine `has_slayers_of_tyrants_vs_target` (ranged + melee) | — |
| Sentinel Storm | row, ShootingPhase shoot-again state, SentinelStormDialog, AI handler | `ork11e_infested_war_zone_defender_saves` steps removed |
| Moment Shackle (10e) | FightPhase queue/actions, MomentShackleDialog, FightController + AI handlers | `fight_moment_shackle_ui` retired; `ai_moment_shackle_window`, `aao_lions_melee_provenance` (later deleted by WP-C46), `cus11e_gilded_champion`, `test_fight_phase_scope_end_fight_11e` §I, `test_custodes_codex_other` ported |
| Quicksilver Execution (10e) | MovementPhase fly-over MW | — |
| Captain-General / Dread Foe / Purity of Execution / Advanced Firepower / Sanctified Flames (10e mechanics) | RulesEngine / ShootingPhase / FightPhase helpers | covered by the codex tests above |
| Master of the Stances | already removed with the Ka'tah stance system (WP-C3) | — |

## Legends datasheets (skipped by the import — not implemented)

Venerable Contemptor Dreadnought (Unyielding Ancient, once-per-battle
revival), Venerable Land Raider (Assault Ramp), Aleya (Tactical Perception,
Tenacious Spirit), Valerian (Golden Laurels, Hero of Lion's Gate), Custodian
Guard Sodality with Adrasite Spears (Stand Vigil, re-roll version),
Sagittarum Custodians Sodality (Disintegration Beams, Saturation Volleys),
Custodian Guard Sodality with Pyrithite Spears (No Foe Shall Stand). No army
file can field them.
