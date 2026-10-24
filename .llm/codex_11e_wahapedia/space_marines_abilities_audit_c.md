# Codex: Space Marines (11e) — generic datasheet + wargear ability audit, M4c list (WP-M4c)

Source: `space-marines/SPACE_MARINES_GENERIC.md` § "Datasheet abilities"
(printed text) for the 29 M4c datasheets of `PLAN_SPACE_MARINES.md` § "M4
split". Scope decision SM-D1: the rules apply to ADEPTUS ASTARTES units of a
Space Marine army (`SWCommon.is_sm_army`), 11e only, and only to the M4c
datasheets (a shared name — Strategic Acumen, Raise the Banner, Codex Adept —
is scoped by datasheet so the M4a/M4b datasheets never get a second copy).

"Before" = the game at the WP-M4c base (581a52e): a grep of
UnitAbilityManager / RulesEngine / FactionAbilityManager / EffectPrimitives /
the phases for every name. None of these 49 abilities had a handler (every
name is new on the codex datasheets, `import_report_space_marines.md`). The
four game-dispatched names the codex dropped (Assault Vehicle, Oath of
Moment, Objective Secured, Target Elimination) belong to none of the M4c
datasheets (Assault Vehicle is a Custodes row; Objective Secured / Target
Elimination were the index Intercessor Squad's, an M4b datasheet; Oath of
Moment is WP-M1's) — nothing to re-key here.

Code: `40k/scripts/codex/space_marines/SMAbilitiesC.gd` (one module; thin,
commented `WP-M4c` hooks elsewhere). Tests: `40k/tests/test_sm11e_abilities_c.gd`
(section numbers in the last column). Windowed scenarios
`40k/tests/scenarios/sp/sm11e_ab_c_*.json` (fixtures built by
`tests/helpers/gen_sm11e_m4c_fixtures.gd`).

Activated abilities are free "Ability" cards in the stratagem-window dialog
(`sm11e_abc_<slug>` ids, cp 0, `is_ability: true`, the WP-C7 / WP-S4 pattern);
the AI scores them synchronously (`ai_score`). Scenarios opt in with
`"sm_abilities_c": true` (ScenarioRunner policy).

Core abilities on these datasheets are engine-handled and checked in §0:
Leader (Captain on Bike leads Outriders), Support (Judiciar, Apothecary,
Ancient, Kaius Konorius, Wardens attach as support), Deep Strike (Kayvaan,
Land Speeder, Assault Intercessors with Jump Packs, Aethon, Caanok, Calgar),
Lone Operative / Stealth (Aethon, Kayvaan), Feel No Pain 6+/5+ (Vulkan,
Caanok, Titus), Scouts 6" (Reivers), Fights First (Judiciar), Deadly Demise /
Damaged (vehicles), TRANSPORT + Firing Deck 2 (Rhino). Faction abilities
Combat Doctrines / Transhuman Strategist are WP-M2a's.

| datasheet | ability | printed text (short) | before | WP-M4c implementation | test / scenario |
|---|---|---|---|---|---|
| Captain on Bike | Strategic Acumen | your Command phase: select a doctrine to be active for this unit until your next Command phase | none | `phase_start` (your Command) card with three doctrine options; writes the SWCommon per-unit doctrine keys on every component (cleared by this module at the start of your next Command phase). Once per phase. AI: tactical engaged / assault melee 6-16" / else devastator | §4, `sm11e_ab_c_command_cards` |
| Captain on Bike | Into the Fray | charged this turn: this unit's melee [CLEAVE 1] | none | RulesEngine [CLEAVE] hook (`melee_cleave`, whole Attached unit) | §2 (A/B attack dice) |
| Gladiator Lancer | Aquilon Optics | ranged attacks vs MONSTER/VEHICLE: re-roll one hit, one wound, one damage roll | none | the engine's single-re-roll grant (Custodes PRIME TARGET flag `cus11e_prime_target`) projected onto the Lancer by the aggregator for each MONSTER/VEHICLE target (absent vs others); spent re-rolls kept in a per-phase ledger | §25 (A/B) |
| Judiciar | Tempormortis | this unit has Fights First | none | FightSequencer.is_fights_first hook (the Judiciar's whole Attached unit) | §24 |
| Kayvaan Shrike | Trifold Path of Shadow | Stealth; -3" detection range | none | RulesEngine.has_stealth_ability + TerrainManager detection-range hooks (Attached unit; 9" floor) | §24 |
| Kayvaan Shrike | Echo of the Ravenspire | end of opponent's Fight phase, unengaged: place in strategic reserves | none | `fight_phase_end` card (opponent's turn) → FightPhase `strategic_reserves` follow-up. AI: no enemy within 12", no objective, before round 5 | §18 |
| Kor'sarro Khan | Trophy Taker | vs CHARACTER: re-roll hit 1s and wound 1s | none | `attack_mods` (Attached unit) | §2 |
| Kor'sarro Khan | For the Khan! | ranged [ASSAULT]; melee [LANCE] | none | EffectPrimitives advance-and-shoot hook; `attack_mods` +1 to wound after a charge move | §2 |
| Land Speeder | Purgation Run | your Shooting phase, when it has shot: normal move up to D6"; no charge this turn | none | `unit_has_shot` card → ShootingPhase `reactive_normal_move` follow-up (D6 rolled on use) + hard charge lock (RulesEngine / ChargePhase hooks) until the end of the turn. AI: 0 (repositioning) | §12 |
| Outrider Squad | Full-throttle Assault | charged: Thunder Hammers +1 to hit and [SUSTAINED HITS 1]; other melee +1 D and [SUSTAINED HITS 1] | none | `attack_mods` per weapon name (Attached unit — a Captain on Bike's hammer too) | §2 (A/B hits) |
| Redemptor Dreadnought | Duty Eternal | S > T: -1 to wound | none | RulesEngine S > T wound-penalty hook | §3 |
| Reiver Squad | Terror Troops (Aura) | enemy model within 3": -1 OC | none | MissionManager.model_oc hook (enemy models only, floor 0) | §20 |
| Reiver Squad | Fearsome Assault | start of the Fight phase: each engaged enemy unit battle-shock roll at -1 | none | FightPhase start hook (automatic roll; single-player / host) | §20, `sm11e_ab_c_fight_cards` |
| Reiver Squad | Grapnel Launchers (wargear) | move through all models; ignore vertical distance | none | MovementPhase `_o6_moves_through_models` + vertical-climb hooks (when the roster lists the wargear) | §20 |
| Reiver Squad | Grav-chutes (wargear) | Deep Strike | none | GameState.unit_has_deep_strike hook | §20 |
| Repulsor | Combat Embarkation | opponent's Charge phase, an enemy selected charge targets: a friendly unengaged ADEPTUS ASTARTES target wholly within 3" embarks; the enemy re-selects | none | NEW `enemy_declares_charge` window (the defender's, after DECLARE_CHARGE, once per declaration) with a picker; embark diffs (TransportManager.can_embark checked); the 11e post-roll target selection no longer sees the embarked unit | §19 |
| Repulsor Executioner | Executioner | ranged vs a unit not below half-strength: +1 to hit | none | `attack_mods` | §2 |
| Rhino | Veiling Smoke (once per phase, per unit) | Smokescreen regardless of other uses, -1 CP | none | StratagemManager override (Custodes override shape, phase stamp on the Rhino) | §23 |
| Vulkan He'stan | Seeker of the Unfound | first time set up: select an objective; in range: OC 10, Ld 5+, FNP 4+ | none | `phase_start` card (any phase start once he is on the battlefield, until chosen) with an objective picker; MissionManager OC, CommandPhase Ld, RulesEngine FNP hooks | §7, `sm11e_ab_c_movement_cards` |
| Vulkan He'stan | Forgefather | your Shooting phase: a visible enemy within 24": friendly AA [MELTA]/[TORRENT] attacks vs it +2 S | none | `phase_start` (your Shooting) card with picker; `attack_mods` +2 S (phase) | §8, `sm11e_ab_c_shooting_cards` |
| Company Heroes / Ancient / Wardens of Ultramar | Raise the Banner | end of your Movement phase, controlling an objective: secured | none | MovementPhase end hook (next to Thievin' Scavengers) → MissionManager.secure_objective | §26, `sm11e_ab_c_movement_cards` |
| Company Heroes | Command Squad | attacks that target this unit: -1 to wound | none | EffectPrimitives -1-to-wound-defence hook (Attached unit) | §3 |
| Apothecary | Narthecium | your Command phase: this unit heals D3+1 | none | `phase_start` (your Command) card when damaged; heal diffs | §5, `sm11e_ab_c_command_cards` |
| Ancient | Honour of the Company | this unit +1 OC | none | MissionManager.model_oc hook (Attached unit) | §26, `sm11e_ab_c_movement_cards` |
| Assault Intercessors with Jump Packs | Hammer of Wrath | ends a charge move: an engaged enemy, D6 per engaged model, 4+ = 1 MW | none | `unit_ended_charge_move` card with picker; mortal wounds | §15 |
| Aethon Shaan | Master of Shadows | your Command phase: a friendly AA INFANTRY unit re-rolls charge rolls until your next Command phase | none | `phase_start` (your Command) card with picker; EffectPrimitives / ChargePhase charge re-roll hooks | §6, `sm11e_ab_c_command_cards` |
| Aethon Shaan | Blackwing Mantle (once per phase, per army) | Heroic Intervention regardless of other uses, -1 CP | none | StratagemManager override | §23 |
| Caanok Var | Cold and Calculating | selected to shoot/fight: [LETHAL HITS: MV] or [SUSTAINED HITS 1: non-MV] (both with the tactical doctrine) | none | `unit_selected_to_shoot` / `unit_selected_to_fight` card with options; `attack_mods` per target (phase) | §11 |
| Caanok Var | Cerebrex Logic Engine | Declare Battle Formations: an AA INFANTRY unit has Scouts 6" | none | FormationsPhase action SM11E_FORMATION_GRANT + dialog section; GameState scouts hooks. AI picks at confirm | §21, `sm11e_ab_c_formations` |
| Suboden Khan | Spear of Chogoris | ranged [ASSAULT]; advance and charge; assault doctrine: +1 advance and charge rolls | none | EffectPrimitives hooks; MovementPhase advance-roll and ChargePhase charge-roll hooks | §22 |
| Suboden Khan | Skilled Riders | this unit has Mobile | none | the engine's MOBILE grant (`ork11e_mobile`) written on every component at each phase transition | §22 |
| Cato Sicarius | Captain of the Honour Guard | army includes Marneus Calgar: Leader -> Support | none | CharacterAttachmentManager.attachment_role hook | §23 |
| Cato Sicarius | Knight Champion of Macragge (once per phase, per army) | opponent's Movement phase, an enemy ends a move within 8", unengaged: normal move up to 6" | none | `enemy_ended_move` card → `reactive_normal_move` follow-up. AI: 0 | §16 |
| Cato Sicarius | Honour or Death | Heroic Intervention on this unit -1 CP | none | StratagemManager discount (can_use, use, preview) | §23 |
| Victrix Honour Guard | Glory of Ultramar | opponent's Shooting phase, a model destroyed by those attacks: surge up to D6" | none | `enemy_has_shot` card (ShootingPhase post-shot ctx now carries `models_destroyed_unit_ids`) → `surge_move` follow-up. AI: 0 | §17 |
| Victrix Honour Guard | Honour Guard of Macragge | attacks that target this unit: -1 to wound | none | EffectPrimitives -1-to-wound-defence hook | §3 (A/B) |
| Victrix Honour Guard | Banner of Macragge (wargear) | end of your Movement phase objective secured; once per battle (army) when selected to fight: melee +1 A and S | none | Raise the Banner hook; `unit_selected_to_fight` card (once per battle) | §14, §26 |
| Captain Titus | Press the Attack | melee [SUSTAINED HITS 1: non-MV]; assault doctrine: [SUSTAINED HITS 1] | none | `attack_mods` | §2, `sm11e_ab_c_fight_cards` |
| Captain Titus | Righteous Fury (once per battle, per army) | Fight phase: melee +1 S; when fought, heals D3 (2D3 after a kill) | none | `unit_selected_to_fight` card; FightPhase "has fought" hook heals | §13, `sm11e_ab_c_fight_cards` |
| Captain Titus | Honour of Ultramar | Fight phase, destroyed before his unit fought: 2+ stays | none | FightPhase Fight On Death intercept (this model) | §13 |
| Wardens of Ultramar | Strategium Command | after deployment: redeploy up to three AA units (reserves allowed) | none | FactionAbilityManager redeploy table (3 slots); RedeploymentPhase lists the units. NOT CLICKABLE (pre-existing gap: the Redeployment step has no player controls; the AI skips redeploys) | §27 |
| Eradicator Squad with Heavy Bolters | Overlapping Destruction | your Shooting phase: select an enemy unit; Heavy Bolters vs it [BLAST 1] | none | `phase_start` + `unit_selected_to_shoot` card with picker; `attack_mods` +1 attack per 5 target models per Heavy Bolter (phase) | §9 (A/B), `sm11e_ab_c_shooting_cards` |
| Marneus Calgar | Codex Adept | assault, devastator, tactical doctrines active | none | SWCommon additional-doctrines key on every component at each phase transition | §10, `sm11e_ab_c_movement_cards` |
| Marneus Calgar | Master Tactician | your Movement phase: a visible AA unit within 9" + a doctrine until your next Command phase | none | `phase_start` (your Movement) card: one target per unit, doctrine options | §10, `sm11e_ab_c_movement_cards` |
| Marneus Calgar | Thunderhawk Insertion | Declare Battle Formations: a GRAVIS/PHOBOS/TACTICUS unit has Deep Strike | none | SM11E_FORMATION_GRANT + dialog; GameState Deep Strike hook. AI picks at confirm | §21, `sm11e_ab_c_formations` |
| Invader ATVs | Aggressive Reconnaissance | your Shooting phase: vs an enemy > 6" from other enemies +1 to wound | none | `attack_mods` | §2 |
| Kaius Konorius | Veteran Bodyguard | attached: other CHARACTER models in this unit FNP 4+ | none | RulesEngine.get_unit_fnp hook | §3 |
| Kaius Konorius | Calgar's Champion | this model vs CHARACTER: re-roll hit 1s and wound 1s | none | `attack_mods` (Kaius's own unit dict) | §2 |
| Eradicator Squad with Melta Rifles | Total Obliteration | ranged attacks re-roll damage rolls | none | RulesEngine damage-roll hook (both allocation sites): a variable damage roll below the average is re-rolled once | §25 (A/B) |

## Per-model weapons (default kit and each wargear option) — §1

Before: single-model datasheets with no roster wargear reported their whole
option MENU (a Captain on Bike also held the Plasma Pistol and Thunder Hammer,
a Redemptor every gun, a Rhino the Hunter-killer Missile, an Ancient both the
Bolt Rifle and the Power Weapon); Company Heroes' guns did not resolve per
model (every model had all three rifles); Wardens of Ultramar's six models
each held all nine weapons; Invader ATVs never resolved (its datasheet name
slugs differently from its id).

Root causes and fixes (UnitLoadoutResolver, data):
1. The Wahapedia import gives a weapon printed differently on a datasheet its
   own id ("bolt-pistol-company-heroes" = the "Master-crafted Bolt Pistol",
   "combat-knife-reiver-squad" = the "Monomolecular Combat Knife"); the resolver
   matched kits by the id with the unit suffix stripped. For
   adeptus-astartes / wahapedia-11e composition and option records the kit
   and option slugs are now the weapons' NAME slugs (weapons.json).
2. A single-model codex datasheet with no roster wargear carries its printed
   default kit (`_codex_default_kit_slugs`), not the menu.
3. Wardens of Ultramar: the importer's loadout parser did not read the
   "<Name> is equipped with:" sentences, so every role's kit was empty — the
   six kits written into unitCompositions.json and the parser fixed
   (wahapedia-import.mjs) so a re-run produces them.
4. Datasheets whose name slug differs from their id (Invader ATVs /
   invader-atv) are also indexed under the name slug.

Checked per model with the default kit and every wargear option: Captain on
Bike, Land Speeder, Redemptor, Repulsor, Repulsor Executioner, Rhino, Ancient,
Invader ATVs, Company Heroes, Wardens of Ultramar, Reiver Squad, Eradicators
(both), Outrider Squad, Assault Intercessors with Jump Packs. Reiver Squad and
Eradicator Squad with Heavy Bolters already resolved correctly (every model
carries the same printed kit; the "left unresolved" log line only means there
was nothing to narrow).

NOT fixed (reported): Victrix Honour Guard — the composition is 0-1 Chapter
Ancient, 0-1 Chapter Champion, 1-6 Honour Guard and the roster carries no
model types, so a 3-model unit is read as three Honour Guard (the Champion's
Blades of Honour never resolves). Needs per-model role data in the army file.

## Transports (Rhino, Repulsor, Repulsor Executioner — and every SM transport)

The generated army files print the capacity as "N SPACE MARINES INFANTRY
models" (the codex: "Adeptus Astartes Infantry"); ArmyListManager split it
into the keywords SPACE + MARINES + INFANTRY, which no unit has — nothing
could embark in any Space Marine transport. SPACE MARINES / ADEPTUS ASTARTES
now parse as the one faction keyword ADEPTUS ASTARTES
(`SMAbilitiesC.transport_capacity_keywords`, both parse sites).

Out of scope (other packages): Combat Doctrines / Transhuman Strategist /
Librarius (M2a); detachments, enhancements, stratagems (M2a/M2b/M3a/M3b);
the M4a / M4b datasheets.
