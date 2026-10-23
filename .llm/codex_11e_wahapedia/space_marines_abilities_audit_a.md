# Codex: Space Marines (11e) — generic datasheet + wargear ability audit, list A (WP-M4a)

Source: `space-marines/SPACE_MARINES_GENERIC.md` § "Datasheet abilities"
(printed text) for the 29 M4a datasheets of `PLAN_SPACE_MARINES.md`, plus the
Librarius army rule's psyker-level budget for their Librarians. Scope SM-D1:
the rules apply to a unit of one of these datasheets in a Space Marine army
(`SWCommon.is_sm_army` — Space Marines / Adeptus Astartes or any chapter), 11e.

"Before" = the game at the WP-M4a base (581a52e): a grep of
UnitAbilityManager / RulesEngine / FactionAbilityManager / EffectPrimitives /
the phases for every name. Only four names had any 10e behaviour:
Omni-scramblers (the 10e 12" reinforcement-denial ring — live), Helix
Gauntlet (a 10e FNP 6+ ABILITY_EFFECTS row, display-only: "passive" rows are
never applied), Storm Shield / Litany of Hate (the WP-S4 Space Wolves rows,
gated to SPACE WOLVES datasheets) and SUPREME COMMANDER (FormationsPhase,
case-insensitive — already engine-handled). None of the four names the SM
import report lists as dropped (Assault Vehicle, Oath of Moment, Objective
Secured, Target Elimination) is on an M4a datasheet.

Code: `40k/scripts/codex/space_marines/SMAbilitiesA.gd` (one module; thin,
commented `WP-M4a` hooks elsewhere). Tests: `40k/tests/test_sm11e_abilities_a.gd`
(section numbers in the last column). Windowed scenarios:
`40k/tests/scenarios/sp/sm11e_ab_a_*.json`. Fixtures:
`40k/tests/helpers/gen_sm11e_m4a_fixtures.gd` -> `tests/saves/sm11e_m4a_*`.

Activated abilities are free "Ability" cards in the stratagem-window dialog
(`sm11e_ab_a_<slug>` ids, cp 0, `is_ability: true`), the WP-C7 / WP-S4
pattern; the AI scores them synchronously (`ai_score`). Scenarios opt in with
top-level `"sm_abilities_a": true` (ScenarioRunner policy).

Core abilities on these datasheets (Leader, Support, Deep Strike, Scouts 6"/8",
Infiltrators, Stealth, Lone Operative, Feel No Pain 5+, Deadly Demise, Damaged,
Hover, TRANSPORT capacity) are engine-handled — §0 checks they resolve.
Faction abilities Combat Doctrines / Transhuman Strategist / Librarius are
WP-M2a's (Strategic Acumen, Codex Adept and Author of the Codex write the
SWCommon doctrine STATE; the doctrine EFFECTS for non-Space-Wolves armies
arrive with M2a).

| datasheet | ability | printed text (short) | before | WP-M4a implementation | test § / scenario |
|---|---|---|---|---|---|
| Apothecary Biologis | Vivispectral Analysis Targeting | this unit's attacks [LETHAL HITS: non-VEHICLE] | none | `attack_mods` lethal vs a non-VEHICLE target, whole Attached unit (Support) | §2 |
| Land Raider, Land Raider Crusader | Assault Ramp | your Movement phase, ends a normal move: embarked units can make an assault disembark move | none | `unit_ended_normal_move` card -> the `assault_disembark` follow-up (READIED BRAWLERS machinery) + DisembarkMove.select_mode hook (assault mode, 18.06) for that follow-up; once per phase | §10, `sm11e_ab_a_movement_cards` |
| Land Raider | Power of the Machine Spirit | ranged: re-roll one hit roll, re-roll one wound roll | none | RulesEngine re-roll-one hook (shared with Magna Imperator) — once per phase per unit, ranged only, not snap shooting | §2 |
| Land Raider Crusader | Fury of the Machine Spirit | ranged vs a unit within 12": [LETHAL HITS] | none | `attack_mods` lethal | §2 |
| Bladeguard Veteran Squad | Bladeguard (once per turn, per unit) | Fight phase, selected to fight / targeted: melee +1 to hit, or attacks that target this unit -1 to hit | none | `unit_selected_to_fight` + `enemy_targets_unit_fight` card with two variants; flag until the end of the phase; once-per-turn ledger | §3, `sm11e_ab_a_bladeguard` |
| Captain, Captain with Jump Pack, Captain in Terminator Armour | Strategic Acumen | your Command phase: select one doctrine active for this unit until your next Command phase | none | `command_phase_main` card with three doctrine variants; SWCommon per-unit doctrine (`sw11e_doctrine` + expiry) on every component; own expiry at the start of your next Command phase | §4, `sm11e_ab_a_command_cards` |
| Captain | Finest Hour (once per battle) | selected to fight: this model's melee +3 A, [DEVASTATING WOUNDS] | none | `unit_selected_to_fight` card; phase-scoped flag on the Captain's own unit; UAM once-per-battle ledger | §4, `sm11e_ab_a_fight_cards` |
| Captain, Captain with Jump Pack, Chaplain in Terminator Armour | Relic Shield (wargear) | +1 W | none | army load (ArmyListManager hook): +1 W when the roster's wargear names a Relic Shield; idempotent | §1, `sm11e_ab_a_wargear` |
| Lieutenant with Combi-weapon | Priority Target Identified (once per battle) | your Command phase: a visible terrain feature is identified until the end of the turn; enemy within it +3" detection range | none | `command_phase_main` card with a terrain picker (StratagemChoiceDialog); faction-state stamp; TerrainManager detection-range hook | §5, `sm11e_ab_a_command_cards` |
| Lieutenant with Combi-weapon | Evade and Survive (once per phase) | opponent's Movement phase, enemy ends a move within 8", unengaged: normal move of up to D3+3" | none | `enemy_ended_move` card -> reactive normal move follow-up | §5, `sm11e_ab_a_evade_and_survive` |
| Librarian in Terminator Armour / in Phobos Armour | Librarian (psyker level 1) + Librarius | psyker level budget per battle round | none | `psychic_budget_check` / `psychic_budget_record` (same flag keys as SWAbilities11e; one place to re-point to M2a) | §6 |
| Librarian in Terminator Armour / in Phobos Armour | Psychic Hood | this unit has FNP 4+ vs psychic attacks | none | RulesEngine `_conditional_fnp` hook (whole Attached unit) | §2 |
| Librarian in Terminator Armour | Might of Heroes (psychic level 1) | Fight phase, not battle-shocked: psychic roll; melee +2 S | none | `phase_start` (either Fight phase) + `unit_selected_to_fight` card; phase-scoped flag; budget | §6, `sm11e_ab_a_fight_cards` |
| Librarian in Terminator Armour | Thunderous Force (psychic level 1) | your Shooting phase: psychic roll; ranged +6" R | none | `phase_start` + `unit_selected_to_shoot` card; RulesEngine range-bonus hook | §6, `sm11e_ab_a_shooting_cards` |
| Captain with Jump Pack | Angel's Wrath | +1 to advance rolls and charge rolls | none | MovementPhase advance-roll + ChargePhase charge-roll hooks (whole Attached unit) | §7 |
| Firestrike Servo-turrets | Sentinel Protocols (once per phase) | FIRE OVERWATCH regardless of other uses; snap shooting hits on unmodified 4+; does not block other uses | none | StratagemManager override (`_cus11e_stratagem_override` shape, not counted against the limit), FIRE OVERWATCH offer gate, RulesEngine snap BS 4 + no hit modifiers, movement_phase_end re-offered after a FIRE OVERWATCH while another use is possible | §8, `sm11e_ab_a_sentinel_protocols` |
| Drop Pod | Drop Pod Assault | must start in strategic reserves; ingress in your first Movement phase; on set-up, embarked units disembark more than 8" from enemies | none | FormationsPhase: undeclared Drop Pods go to strategic reserves; round-1 ingress (MovementPhase hooks); after set-up the new `sm11e_drop_pod_landed` window card starts the assault disembark; disembark validation refuses set-ups within 8" of an enemy | §11, `sm11e_ab_a_drop_pod` |
| Drop Pod | Deployment Complete | set up and emptied: no embarking | none | TransportManager.can_embark refusal | §11 |
| Ballistus Dreadnought | Ballistus Strike | ranged vs a unit within 24": [SUSTAINED HITS 1] | none | `attack_mods` sustained | §2 |
| Chaplain on Bike / with Jump Pack / in Terminator Armour | Litany of Hate | melee [LANCE] | SW row only (Wolf Priest) | `attack_mods` +1 to wound after a charge move (the 11e [LANCE] convention), whole Attached unit | §2 |
| Chaplain on Bike | Catechism of Fire | selected to shoot: a visible enemy — ranged vs it [DEVASTATING WOUNDS] | none | `unit_selected_to_shoot` card with picker (planned target first); phase-scoped | §13, `sm11e_ab_a_shooting_cards` |
| Chaplain with Jump Pack | Exhortation of Rage | at/below half-strength: melee re-roll wound rolls | none | `attack_mods` (combined Attached-unit strength) | §2 |
| Storm Speeder Hammerstrike | Hammerstrike | ranged vs a unit within a terrain area: [SUSTAINED HITS 1] | none | `attack_mods` (TerrainManager.pieces_model_within) | §2 |
| Chaplain in Terminator Armour | Zealous Fortitude | FNP 4+ vs mortal wounds | none | `_conditional_fnp` hook | §2 |
| Terminator Assault Squad | Teleport Homer (once per battle) | start of the battle: token; Rapid Ingress -1 CP, set up within 3" of it and not within 8" of an enemy; removed when an enemy ends a move within 1" | none | round-1 `phase_start` card with a spot picker (objectives / next to a friendly unit); RAPID INGRESS -1 CP + "within 3\"" set-up validation + token removal; lazy enemy-within-1" removal | §12, `sm11e_ab_a_round1_cards` |
| Terminator Assault Squad | Terminatus Assault | charged: Lightning Claws [SH1 vs non-MV], Thunder Hammers [SH1 vs MV] | none | `attack_mods` per weapon name + target keywords | §2 |
| Terminator Assault Squad | Storm Shield (wargear) | +1 W | SW row (SW datasheets only) | army load: the first N models (N from "Nx Storm Shield"); shared model marker with SWAbilities11e | §1, `sm11e_ab_a_wargear` |
| Librarian in Phobos Armour | Shrouding (psychic level 1) | when an enemy targets this unit: psychic roll; attacks vs it -1 to hit until end of phase | none | defender's reactive dialog (`enemy_targets_unit_shooting`) + `enemy_targets_unit_fight` card | §6, `sm11e_ab_a_shrouding` |
| Librarian in Phobos Armour | Soul Sight (psychic level 1) | your Shooting phase: psychic roll; a visible enemy: ranged attacks vs it [IGNORES COVER] | none | `phase_start` + `unit_selected_to_shoot` card with picker; phase-scoped; aggregator `ignores_cover` | §6, `sm11e_ab_a_shooting_cards` |
| Storm Speeder Hailstrike | Hailstrike | has shot: an enemy hit — friendly AA ranged vs it [IGNORES COVER] | none | `unit_has_shot` card with the hit units; phase-scoped | §14 |
| Infernus Squad | Driven from Cover | as Hailstrike | none | as Hailstrike | §14, `sm11e_ab_a_shooting_cards` |
| Inceptor Squad | Meteoric Descent | made an ingress move this turn: ranged +1 to hit | none | `attack_mods` (arrival stamp) | §15 |
| Inceptor Squad | Parabolic Jetleap | end of your opponent's Fight phase, unengaged: strategic reserves | none | `fight_phase_end` card (Custodes Take Wing shape) | §15, `sm11e_ab_a_parabolic_jetleap` |
| Iron Father Feirros | Master of the Forge | your Movement phase, start/end of move: AA VEHICLE within 3" heals 3, ignores BS/hit/wound modifiers until your next Movement phase | none | `unit_selected_to_move` / `unit_ended_*_move` card (Gift of the Iron Wolf shape) | §16 |
| Iron Father Feirros | Rites of Tempering | S > T: -1 to wound | none | RulesEngine wound-penalty hook | §2 |
| Iron Father Feirros | Iron Father | within 3" of an AA VEHICLE: Lone Operative | none | RulesEngine.has_lone_operative hook | §16 |
| Infiltrator Squad | Omni-scramblers | your Shooting phase: a visible enemy within 18" is detected (+3" detection range) | 10e 12" reinforcement denial (live) | `phase_start` card with picker; TerrainManager detection-range hook; the 10e denial is RETIRED for these units (GameState + AIDecisionMaker gates) | §17, `sm11e_ab_a_shooting_cards` |
| Infiltrator Squad | Helix Gauntlet (wargear) | your Command phase: this unit heals D3 | 10e FNP 6+ row (display only) | `command_phase_main` card when damaged; UAM row description updated | §17, `sm11e_ab_a_command_cards` |
| Captain in Terminator Armour | Unstoppable Valour | re-roll charge rolls | none | EffectPrimitives charge re-roll hook | §7 |
| Brutalis Dreadnought | Brutalis Charge (once per phase) | CRUSHING IMPACT regardless of other uses, -1 CP | none | StratagemManager override (cost -1, not counted against the limit) | §9 |
| Roboute Guilliman | Codex Adept | assault, devastator and tactical doctrines active for this unit | none | SWCommon `sw11e_doctrine_extra` at every phase transition (writer marker `sm11e_aba_extra`, other writers kept) | §18, `sm11e_ab_a_movement_cards` |
| Roboute Guilliman | Primarch of the XIII (Aura) | friendly AA units within 6": re-roll hit 1s and wound 1s | none | `attack_mods` (Guilliman's own unit included) | §18 |
| Roboute Guilliman | Author of the Codex | your Movement phase: a visible friendly AA unit within 12" + a doctrine, in addition, until your next Command phase | none | Movement `phase_start` card: variants (doctrine) + unit picker; additional-doctrine key | §18, `sm11e_ab_a_movement_cards` |
| Roboute Guilliman | Leader of Astartes | within 3" of AA INFANTRY: Lone Operative | none | has_lone_operative hook | §18 |
| Roboute Guilliman | SUPREME COMMANDER | must be your WARLORD | FormationsPhase (case-insensitive) | engine-handled — verified | §0 |
| Thunderhawk Gunship | Aerial Assault | ends a normal move: embarked units whose every model has Deep Strike can assault disembark | none | `unit_ended_normal_move` card; the follow-up's candidates filtered to Deep Strike units | §10 |
| Thunderhawk Gunship | Thunderhawk Cluster Bombs | ends a normal/advance move: an enemy moved over — six D6, each 3+ = 1 MW | none | `unit_ended_*_move` card; the move's start positions ride the window ctx; straight-line swept bases | §19 |
| Techmarine | Techmarine | within 3" of an AA VEHICLE: Lone Operative | none | has_lone_operative hook | §16 |
| Techmarine | Blessings of the Omnissiah | as Master of the Forge (heals D3, hit/wound only) | none | as Master of the Forge | §16, `sm11e_ab_a_movement_cards` |
| Vanguard Veteran Squad with Jump Packs | Vanguard Assault | charged: melee +1 A | none | `attack_mods` | §2 |
| Vanguard Veteran Squad with Jump Packs | Combat Shield (wargear) | 5+ InSv | none | army load: the first N models get invuln 5 | §1, `sm11e_ab_a_wargear` |
| Invictor Tactical Warsuit | Forward Assault Warsuit | start of round 1: an enemy is the mark; re-roll wound 1s vs it; new mark when destroyed | none | `phase_start` card (round 1 until chosen, and after the mark died) with picker; `attack_mods` | §20, `sm11e_ab_a_round1_cards` |

Datasheet weapon resolution (default kit + each wargear option, §1):
- FIXED (data): single-model datasheets whose army entry lists the whole
  option menu and no roster wargear fired every option (Land Raider: HK
  Missile + Multi-melta + Storm Bolter; Captain: Neo-volkite + Plasma Pistol +
  Power Fist; Captain with Jump Pack, Firestrike Servo-turrets, Captain in
  Terminator Armour, Brutalis Dreadnought, Thunderhawk, Invictor). The list
  build stamps the printed default kit as roster wargear when none is listed
  (`DEFAULT_KIT`), so the resolver narrows to the loadout.
- FIXED (resolver logic): an option whose bundle is a non-weapon item
  ("Master-crafted Bolter -> Relic Shield", "Storm Bolter -> Relic Shield",
  Thunder Hammer + Relic Shield) was never detected as taken —
  `UnitLoadoutResolver._base_kit_slugs` now also reads the roster's
  non-weapon wargear items.
- FIXED (data): the transport capacity of the Land Raider / Crusader / Drop
  Pod / Thunderhawk ("SPACE MARINES INFANTRY models") parsed to the keywords
  SPACE + MARINES + INFANTRY — no unit has them, nothing could embark. Read as
  ADEPTUS ASTARTES + INFANTRY at list build (M4a datasheets only).
- NOT FIXED (engine-wide, reported): a single model carrying two or more of
  the same weapon (Land Raider 2x Godhammer Lascannon / 2x Hurricane Bolter,
  Thunderhawk 2x Lascannon / 4x Twin Heavy Bolter) fires it once: weapon ids
  are unique per model in the shooting pipeline.
- NOT FIXED (reported): the same SPACE MARINES INFANTRY keyword split hits
  every other Space Marine transport (Rhino, Razorback, Impulsor, Repulsor,
  Repulsor Executioner, Land Raider Redeemer — M4b/M4c datasheets).

Out of scope (other packages): Combat Doctrines selection / effects,
Transhuman Strategist, Librarius generalisation (WP-M2a); detachments and
enhancements (M2a/M2b); stratagems (M3a/M3b); the other 58 datasheets (M4b/M4c).
