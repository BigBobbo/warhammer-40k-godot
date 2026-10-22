# Codex: Space Marines (11e) — Space Wolves datasheet + wargear ability audit (WP-S4)

Source: `space-marines/SPACE_WOLVES.md` § "Datasheet abilities" (printed
text) for the 21 SPACE WOLVES datasheets, plus the Librarius army rule.
Scope decisions SW-D1..D4 (`PLAN_SPACE_WOLVES.md`): the rules apply to
SPACE WOLVES units of a Space Wolves army (`SWCommon.is_sw_army`), 11e only.

"Before" = the game at the WP-S4 base (9026543): a grep of
UnitAbilityManager / RulesEngine / FactionAbilityManager / EffectPrimitives
for every name found **nothing** — no 10e Space Wolves ability handler
existed (the import report lists 0 dropped game-dispatched names), so there
was nothing to re-key or retire. Every row below was "none" before.

Code: `40k/scripts/codex/space_wolves/SWAbilities11e.gd` (one module; thin,
commented hooks elsewhere). Tests: `40k/tests/test_sw11e_abilities.gd`
(section numbers in the last column); windowed scenarios
`40k/tests/scenarios/sp/sw11e_ab_*.json`.

Core abilities on these datasheets (Leader, Deep Strike, Scouts 8",
Infiltrators, Feel No Pain 5+/6+, Deadly Demise 1) are engine-handled — §0
checks they resolve for these units. Faction abilities Combat Doctrines,
Transhuman Strategist and Curse of the Wulfen are WP-S2's.

Activated abilities are free "Ability" cards in the stratagem-window
dialog (`sw11e_ab_<slug>` ids, cp 0, `is_ability: true`), the WP-C7 / WP-O6
pattern; the AI scores them synchronously (`ai_score`).

| datasheet | ability | printed text (short) | before | WP-S4 implementation |
|---|---|---|---|---|
| Logan Grimnar | High King of Fenris (once per battle round, per unit) | your Movement phase: select up to one friendly SW unit in strategic reserves; its ingress move treats the battle round as one higher | none | `phase_start` card (your Movement phase) with a reserves picker; flag on the picked unit for this phase; MovementPhase reads `ingress_battle_round()` (round-1 arrival allowed, opponent-DZ ban lifted in round 2). §12, scenario `sw11e_ab_high_king` |
| Logan Grimnar | Guile of the Wolf | start of each phase: assault, devastator and tactical doctrines active for this unit | none | writes `flags.sw11e_doctrine_extra = [all three]` on every component of Logan's (Attached) unit at every phase transition (SWCommon API), cleared when Logan is gone. §11 |
| Ragnar Blackmane | Battle-lust | charged this turn: this model's melee +2 A | none | `attack_mods` (Ragnar's own attacks). §2 |
| Ragnar Blackmane | War Howl | attached to Blood Claws: unit melee +1 S and [SUSTAINED HITS 1]; attached to Wolf Guard Headtakers: advance does not prevent a charge | none | `attack_mods` (whole Attached unit, only while led Blood Claws); advance-and-charge hook (only while led Headtakers). §2 |
| Njal Stormcaller | Wind Walker | ranged [ASSAULT]; advance roll can be changed to a 6 | none | EffectPrimitives advance-and-shoot hook; MovementPhase advance roll = 6 (a roll: modifiers apply). §3 |
| Njal Stormcaller | High Rune Priest (psyker level 3) | psychic abilities listed below | none | Librarius budget: psyker level 3 per battle round (each power psychic level 1); one use of each power per phase. §4 |
| Njal Stormcaller | Murderous Hurricane (psychic level 1) | your Movement phase, not battle-shocked: psychic roll (1 = battle-shocked); a visible enemy within 12" cannot make snap-shooting attacks | none | `phase_start` (Movement) + `unit_ended_normal_move`/`unit_ended_advance_move` (Njal's unit) card with enemy picker; flag until end of turn; FIRE OVERWATCH refuses that unit. §4, scenario `sw11e_ab_njal_psychic` |
| Njal Stormcaller | Storm Caller (psychic level 1) | an enemy unit targets this unit, not battle-shocked: psychic roll; -3" detection range until end of phase | none | card in the defender's `enemy_targets_unit_shooting` reactive dialog; TerrainManager detection-range hook (-3", floor 9" still applies). Melee targeting not offered (detection range is a shooting rule). §4 |
| Njal Stormcaller | Tempest's Wrath (psychic level 1) | your Shooting phase, not battle-shocked: psychic roll; a visible enemy within 18" is suppressed until the start of your next turn (-1 to hit) | none | `phase_start` (Shooting) card with enemy picker; `suppressed` flag (owner/turn stamp) → -1 to hit for all its attacks. §4, scenario `sw11e_ab_njal_psychic` |
| Ulrik the Slayer | Slayer's Oath | start of the first battle round: select up to one enemy CHARACTER/MONSTER/VEHICLE unit; attacks vs it ignore modifiers to BS/WS and hit rolls | none | `phase_start` card in battle round 1 (until chosen) with picker; `attack_mods` ignore_hit_penalties vs that unit (whole Attached unit). §5, scenario `sw11e_ab_slayers_oath` |
| Ulrik the Slayer | Oathbound | melee +1 to hit; or vs the oath: melee +1 hit and +1 wound | none | `attack_mods` (whole Attached unit). §5 |
| Bjorn the Fell-Handed | Legendary Tenacity | attacks with S > T: -1 to wound | none | incoming wound-penalty hook. §6 |
| Bjorn the Fell-Handed | Ancient Tactician (once per turn, per army) | stratagem targeting this unit: -1 CP | none | StratagemManager CP hook (can_use + use) + once-per-turn army ledger. §6 |
| Blood Claws | Berserk Charge | advance does not prevent a charge | none | advance-and-charge hook. §7 |
| Grey Hunters | Old Greymanes | Declare Battle Formations: split into two units, as equal as possible | none | FormationsPhase action `SW11E_SPLIT_UNIT` (diffs) + "UNIT SPLITS" section with a Split button in the formations dialog (rebuilds the dialog so the new half can be led / put in reserves). AI keeps units whole. §8, scenario `sw11e_ab_unit_split` |
| Grey Hunters | Cunning Hunters | Fight phase, unit within range of an objective: melee +1 S, +1 AP | none | `attack_mods`. §7 |
| Iron Priest | Gift of the Iron Wolf | your Movement phase, start or end of this unit's move: a friendly SW VEHICLE model within 3" heals D3 and its attacks ignore hit/wound modifiers until your next Movement phase; once per vehicle per phase | none | `unit_selected_to_move` / `unit_ended_normal_move` / `unit_ended_advance_move` card (Iron Priest's unit) with vehicle picker; one use per Iron Priest per phase; heal diffs; flag read by `attack_mods` (ignore hit and wound penalties). §9, scenario `sw11e_ab_gift_of_the_iron_wolf` |
| Iron Priest | Iron Priest | within 3" of a friendly SW VEHICLE unit: Lone Operative | none | RulesEngine.has_lone_operative hook. §9 |
| Iron Priest | Judgement of the Omnissiah | this model's attacks vs an enemy engaged with a friendly SW VEHICLE: re-roll wound rolls | none | `attack_mods` (Iron Priest's own attacks). §9 |
| Wulfen | Savage Frenzy | engaged enemy (not MONSTER/VEHICLE) falling back must use desperate escape; -1 to those hazard rolls if battle-shocked | none | FallBackMove + MovementPhase hooks next to Corner the Quarry. §10 |
| Wulfen / Wulfen with Storm Shields | Death Totem (wargear) | unit melee re-roll hit rolls of 1 | none | `attack_mods`. §10 |
| Murderfang | Murder-maker | Fight phase: a friendly WULFEN model within 6" destroyed, its unit not yet selected to fight: 4+ it stays until its unit has fought / end of phase | none | FightPhase Fight On Death intercept (shared 05.04.05 mechanic). §13 |
| Murderfang | Bestial Fury | re-roll advance and charge rolls | none | EffectPrimitives re-roll hooks. §10 |
| Murderfang | Force of Untamed Destruction | cannot be your WARLORD | none | FormationsPhase warlord block (same path as Anathema Psykana). §10 |
| Arjac Rockfist | Champion of the Kingsguard | this model's attacks vs a CHARACTER unit: re-roll hit 1s and wound 1s | none | `attack_mods` (Arjac's own attacks). §6 |
| Arjac Rockfist | Anvil of Endurance | Fight phase: a model in this unit destroyed, unit not yet selected to fight: 4+ stays | none | Fight On Death intercept (whole Attached unit). §13 |
| Wolf Guard Terminators | Rugged Resilience | S > T: -1 to wound | none | incoming wound-penalty hook. §6 |
| Wolf Guard Terminators / Wolf Guard Battle Leader | Storm Shield (wargear) | this model has +1 W | none | army load (ArmyListManager hook): the first N models (N = "Nx Storm Shield" in the roster wargear) get +1 W; idempotent. §1 |
| Thunderwolf Cavalry / Wolf Guard Headtakers | Storm Shield (wargear) | this model has a 4+ InSv | none | army load: the first N eligible models (Headtaker models, not Hunting Wolves) get model invuln 4. §1 |
| Thunderwolf Cavalry | Thunderous Charge | charged this turn: melee +1 S, +1 D | none | `attack_mods`. §7 |
| Fenrisian Wolves | Predatory Instinct (once per battle round, per unit) | opponent's Movement phase, enemy ends a move within 8", unengaged: normal move up to D6" | none | `enemy_ended_move` card → reactive normal move follow-up. §14, scenario `sw11e_ab_predatory_instinct` |
| Fenrisian Wolves | Hunting Hounds | within 6" of a friendly SW CHARACTER (not WULFEN), not battle-shocked: +1 OC | none | MissionManager.model_oc hook. §15 |
| Wolf Guard Headtakers / Wolf Scouts | Hunting Hounds | as above: Hunting Wolf models +1 OC | none | model_oc hook, Hunting Wolf models only (the W1 models; their printed OC is 0 — the roster gives them the unit's OC 1, corrected in the hook). §15 |
| Venerable Dreadnought | Fervour of the Ancients | friendly SW units within 6": +1 advance, +1 charge | none | MovementPhase advance-roll + ChargePhase charge-roll hooks. §16 |
| Venerable / Wulfen Dreadnought | Blizzard Shield (wargear) | 4+ InSv | none | army load: model invuln 4 when the roster has a Blizzard Shield. §1 |
| Wolf Priest | Healing Balms | your Command phase: this unit heals D3+1 | none | `phase_start` (your Command phase) card when the unit is damaged; heal diffs (wounded model first, else a destroyed model returns with 1 W). §17 |
| Wolf Priest | Litany of Hate | unit melee [LANCE] | none | `attack_mods` +1 to wound after a charge move (whole Attached unit). §17 |
| Wolf Guard Battle Leader | Tempered Ferocity | unit attacks [SUSTAINED HITS 1]; vs enemy within 6" re-roll hit 1s | none | `attack_mods`. §18 |
| Wolf Guard Battle Leader | Heroic Last Stand | Fight phase: this model destroyed, unit not yet selected to fight: 2+ stays | none | Fight On Death intercept (this model only). §13 |
| Wolf Guard Headtakers | Headhunters | start of first battle round: select an enemy unit as quarry; attacks vs it [DEVASTATING WOUNDS] and [PRECISION]; new quarry each time it is destroyed | none | `phase_start` card (round 1 / after the quarry died) with picker; `attack_mods` devastating + precision (ranged and melee consumers). §19 |
| Wolf Guard Headtakers | Let Loose the Wolves | start of Declare Battle Formations: split into Headtakers and Hunting Wolves | none | same FormationsPhase split action; Hunting Wolf half gets the Hunting Wolf profile (M10 T4 Sv6+ W1 Ld8 OC0, BEASTS, Teeth and Claws). §8 |
| Wulfen with Storm Shields | Hammer Blow | Fight phase, this unit has fought: an enemy MONSTER/VEHICLE hit by those attacks is suppressed until the start of your next turn | none | new `unit_has_fought` window (FightPhase, before enemy_has_fought) with a picker; suppressed flag. §20 |
| Wulfen Dreadnought | Violent Fury | two melee weapons: melee [TWIN-LINKED] | none | `attack_mods` re-roll wound rolls when the equipped loadout has 2 melee weapons. §21 |
| Wulfen Dreadnought | Bestial Rage | opponent's Shooting phase, enemy has shot, lost a wound: surge up to D6+1" | none | `enemy_has_shot` card → surge move follow-up (not engaged / battle-shocked). §21 |
| Wolf Scouts | Deadly Stalkers | vs an enemy more than 6" from any other enemy unit: +1 to wound | none | `attack_mods`. §22 |
| Wolf Scouts | Haywire Mine (wargear, once per battle, per unit) | your Shooting phase: visible enemy within 6", D6 2+: D3 MW, or 2D3 vs VEHICLE | none | `phase_start` (Shooting) + `unit_selected_to_shoot` card with picker; mortal wounds; once-per-battle ledger. §22, scenario `sw11e_ab_haywire_mine` |
| (army rule) | Librarius | psyker level budget per battle round | none | `psyker_level` / `can_use_psychic` / `record_psychic_use` in SWAbilities11e (Njal: level 3). §4 |

Out of scope (other packages): Combat Doctrines, Transhuman Strategist,
Curse of the Wulfen, Sons of Russ (WP-S2); the 12 stratagems (WP-S3).
