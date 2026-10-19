# WP-O6 — Codex: Orks (11e) datasheet abilities audit

Every Datasheet / Wargear / psychic ability on the 55 Ork codex datasheets (core and faction abilities — Leader, Deep Strike, Feel No Pain, Deadly Demise, Damaged, Waaagh!, Da Boss, Unstable Energies — belong to other packages).
'Game status before' is the branch base (claude/gracious-shannon-u3z0mf before WP-O6): whether the codex rule existed and under which (10e) name. Logic lives in `40k/scripts/codex/orks/OrkAbilities11e.gd` (slug per ability) with thin hooks in RulesEngine / phases / managers.

| datasheet | ability | printed text (short) | game status before | action taken |
|---|---|---|---|---|
| Warboss | Boss’ Ammo Runt (Once per battle, per unit) | In your Shooting phase, when this unit is selected to shoot, you can use this ability. If | implemented as the old 10e 'Ammo Runt' (different effect) | re-implemented (codex mechanic; old code removed) — activated, unit_selected_to_shoot; +1 to hit for the Warboss model's ranged attacks |
| Warboss | Might Is Right | If this unit made a charge move this turn, this model’s melee attacks have: +3 A.+2 S. | partially: a 10e-era 'Might is Right' ABILITY_EFFECTS row (+1 A always) | re-implemented (codex mechanic; old code removed) — charged: melee +3 A / +2 S (old row made inert) |
| Warboss | Intimidating Motivation (Once per battle round, per army) | In your Movement phase, at the start or end of this unit’s move, you can select one friend | not at all | implemented (OrkAbilities11e) — activated, start/end of move; once per battle round per army |
| Warboss In Mega Armour | Krushin’ Impetus | When this unit ends a charge move, you can select one enemy unit engaged with this unit. I | not at all (the 10e 'Dead Brutal' Waaagh! damage rider removed) | implemented (OrkAbilities11e) — activated, unit_ended_charge_move; D6 per engaged model, 3+ = 1 MW |
| Warboss In Mega Armour | Intimidating Motivation (Once per battle round, per army) | In your Movement phase, at the start or end of this unit’s move, you can select one friend | not at all | implemented (OrkAbilities11e) — activated, start/end of move; once per battle round per army |
| Weirdboy | Waaagh! Energy (psyker level 1) | This model has the psychic abilities listed in the Psychic Abilities section (see above). | implemented (10e psyker rider) | other package — psyker level marker; the psychic budget is WP-O34's Unstable Energies (OrkArmyRules11e.can_use_psychic), which this module calls |
| Big Mek In Mega Armour | Fix Dat Armour Up (Once per battle, per unit) | In your Command phase, this unit heals 3 wounds.  Place a Grot Oiler token next to the uni | implemented as the old 10e 'Grot Oiler' (heal D3, other timing) | re-implemented (codex mechanic; old code removed) — activated, battle_shock_step_start; once per battle heal 3 |
| Big Mek In Mega Armour | More Dakka | This unit’s ranged attacks have: [Ignores Cover]. If this unit is riled up, [Sustained Hit | partially: 10e-era row (riled-up rider missing) | re-implemented (codex mechanic; old code removed) — ranged [IGNORES COVER]; riled up: [SUSTAINED HITS 1] |
| Big Mek In Mega Armour | Kustom Force Field | This unit has 4+ InSv against ranged attacks. | partially: 10e 5++ aura row | re-implemented (codex mechanic; old code removed) — 4+ invuln vs ranged for the (attached) unit |
| Ghazghkull Thraka | Da Grand Warlord's Ladz | While this unit is within 3" of another friendly Orks Infantry unit, this unit has Lone Op | not at all (the 10e 'Da Boss' Ladz' was a -1-to-wound rider, removed) | implemented (OrkAbilities11e) — conditional Lone Operative (own bodyguard excluded) |
| Ghazghkull Thraka | Makari, Hoist Dat Banner! (Once per battle, per army) | In your Movement phase, you can select a number of friendly ORKS units equal to or less th | not at all | implemented (OrkAbilities11e) — activated, movement_phase_start; up to battle-round-number units riled up, once per battle |
| Ghazghkull Thraka | Prophet of da Great Waaagh! (Aura) | While a friendly ORKS unit is within 6" of this unit, that unit’s melee attacks have: +1 t | partially: 10e Waaagh!-only rider | re-implemented (codex mechanic; old code removed) — aura 6": melee +1 hit / +1 wound |
| Boss Snikrot | Kunnin’ Infiltrator | At the end of your opponent’s Fight phase, if each model in this unit is hidden and unenga | implemented under the same name with the 10e redeploy text (the 10e 'Red Skull Kommandos' cover rider removed) | re-implemented (codex mechanic; old code removed) — activated, end of opponent's Fight phase: hidden + unengaged -> strategic reserves |
| Boss Snikrot | Deff from the Shadows (First battle round onwards) | At the end of your opponent’s Movement phase, if this unit is in strategic reserves, this | not at all | NOT implemented — needs Rapid-Ingress plumbing at the end of the opponent's Movement phase (round 1 allowed) |
| Mek | Kustom Dakka | This unit’s ranged attacks have [Ignores Cover]. | implemented (Shoota Boyz stratagem name clash; the ability itself absent) | implemented (OrkAbilities11e) — ranged [IGNORES COVER] |
| Mek | Clever Know-wotz | In your Movement phase, at the start or end of this unit’s move, you can select one friend | implemented as the old 10e 'Mekaniak' (heal D3) | re-implemented (codex mechanic; old code removed) — activated, start/end of move; heal D3 + the vehicle's attacks +1 to hit until your next Movement phase |
| Painboy | Crude Surgery | In your Command phase, this unit heals 3 wounds. | not at all (the 10e 'Dok's Toolz' FNP 5+ removed) | implemented (OrkAbilities11e) — activated, battle_shock_step_start (auto heal 3 at Command exit if unused) |
| Painboy | Catch Dat Red Bit (Once per battle, per unit) | When this model uses its Crude Surgery ability, you can add D3 to the number of wounds hea | implemented as the old 10e 'Grot Orderly' | re-implemented (codex mechanic; old code removed) — Crude Surgery option +D3, once per battle |
| Boyz | Ammo Runts (Once per battle, per unit) | In your Shooting phase, when this unit is selected to shoot, you can use this ability. If | implemented as the old 10e 'Ammo Runt' | re-implemented (codex mechanic; old code removed) — activated, unit_selected_to_shoot; +1 to hit (ranged), once per battle |
| Boyz | Tide of Muscle | In the Fight phase, if this unit made a charge move this turn, this unit’s melee attacks h | partially: a stratagem-side check | implemented (OrkAbilities11e) — Fight phase + charged: melee [LETHAL HITS] |
| Boyz | Never Too Busy to Fight | Being engaged does not prevent this unit from being eligible to start an action. | not at all | implemented (OrkAbilities11e) — ActionsManager: engaged does not block starting an action |
| Gretchin | Downtrodden | For the purposes of transport capacity, each 2 Gretchin models (rounding up) take up the s | not at all | implemented (OrkAbilities11e) — TransportManager: 2 Gretchin per transport space |
| Gretchin | Thievin’ Scavengers | At the end of your Movement phase, if this unit is controlling an objective, that objectiv | implemented under the same name as a 10e start-of-Movement CP roll | re-implemented (codex mechanic; old code removed) — end of your Movement phase: controlled objective secured (by the army) |
| Tankbustas | Rokkit Barrage | In your Shooting phase, when this unit has shot, select one enemy unit hit by those attack | not at all (the 10e 'Tank Hunters' +1 hit/wound vs M/V dispatch removed) | implemented (OrkAbilities11e) — post-shot: 1 unit hit auto, 2+ -> unit_has_shot window; battle-shock roll -1 |
| Tankbustas | Bomb Squigs (Once per turn, twice per battle, per unit) | In your Movement phase, when this unit ends a normal move, you can select one visible enem | implemented with the 10e text (once per battle) | re-implemented (codex mechanic; old code removed) — activated, unit_ended_normal_move; once per turn, twice per battle |
| Tankbustas | Pulsa Rokkit (Once per battle, per unit) | In your Shooting phase, when this unit is selected to shoot, you can select one enemy MONS | implemented with the 10e text (own dialog) | re-implemented (codex mechanic; old code removed) — activated, unit_selected_to_shoot; +1 AP and [LETHAL HITS] vs the selected MONSTER/VEHICLE |
| Nobz | Get Out da Way! | While making a charge move, this unit can move through models (excluding MONSTER/VEHICLE m | not at all | implemented (OrkAbilities11e) — flag only: the engine's charge move has no model-crossing gate (end overlap only), so it is effectively always true |
| Nobz | Ammo Runts (Once per battle, per unit) | In your Shooting phase, when this unit is selected to shoot, you can use this ability. If | implemented as the old 10e 'Ammo Runt' | re-implemented (codex mechanic; old code removed) — activated, unit_selected_to_shoot; +1 to hit (ranged), once per battle |
| Nobz | Paired Krumpas | Attacks made with this model’s Kustom Krumpa weapon can re-roll hit rolls and wound rolls. | not at all | implemented (OrkAbilities11e) — Kustom Krumpa re-rolls hit and wound rolls |
| Meganobz | Arrogant Invulnerability | Attacks that target this unit have -1 AP. | not at all | implemented (OrkAbilities11e) — incoming attacks -1 AP (EffectPrimitives worsen AP) |
| Meganobz | Krumpin’ Time | In the Fight phase, if this unit is riled up, this unit has +1 to hit rolls. | partially: 10e-era Waaagh! row | re-implemented (codex mechanic; old code removed) — Fight phase + riled up: +1 to hit |
| Kommandos | Found ’Em! | In your Movement phase, you can select one enemy unit within 12" of this unit. That unit h | not at all | implemented (OrkAbilities11e) — activated, start/end of move; enemy +3" detection range until end of turn (TerrainManager) |
| Kommandos | Taktikal Know-wotz | In the Declare Battle Formations step, you can split this unit into two units, each with a | implemented as the old 10e 'Patrol Squad' split | re-keyed (same mechanic, codex name) — split at deployment; Squad A keeps Bomb Squig, Squad B Found 'Em! |
| Kommandos | Nowhere to Hide | This unit’s attacks that target a hidden unit have +1 to hit rolls. | not at all | implemented (OrkAbilities11e) — +1 to hit vs a hidden unit |
| Kommandos | Bomb Squig (Once per battle, per unit) | In your Movement phase, when this unit ends a normal move, you can select one visible enem | implemented as the 10e 'Bomb Squigs' rider | re-implemented (codex mechanic; old code removed) — activated, unit_ended_normal_move; once per battle |
| Trukk | Pilin’ Out | In your opponent’s Movement phase, when an enemy unit ends a move within 8" of this model, | not at all | NOT implemented — reactive disembark in the opponent's Movement phase needs a new transport flow |
| Stormboyz | Rokkit Charge | When this unit is selected to fight, if this unit made a charge move this turn, you can us | not at all | implemented (OrkAbilities11e) — activated, unit_selected_to_fight; charged: +1 A, +1 S, [HAZARDOUS] |
| Deffkoptas | Deff from Above | In your Shooting phase, if this unit made an ingress move this turn, this unit’s ranged at | partially: 10e-era row | re-implemented (codex mechanic; old code removed) — +1 to hit in your Shooting phase after an ingress move |
| Deffkoptas | Aerial Manoover | At the end of your opponent’s Fight phase, if this unit is unengaged, you can place this u | not at all | implemented (OrkAbilities11e) — activated, end of opponent's Fight phase: unengaged -> strategic reserves |
| Dakkajet | Strafing Run | In your Shooting phase, this unit’s ranged attacks that target a unit (excluding FLY units | not at all | implemented (OrkAbilities11e) — +1 to hit vs non-FLY in your Shooting phase |
| Burna-bommer | Burna Bomb | At the end of your opponent’s Fight phase, select one visible enemy unit (excluding Lone O | not at all | implemented (OrkAbilities11e) — activated, end of opponent's Fight phase: D6 2+ D3 MW; cannot be hidden, ranged [IGNORES COVER] vs it |
| Blitza-bommer | Boom Bomb | At the end of your opponent’s Fight phase, select one visible enemy unit (excluding Lone O | not at all | implemented (OrkAbilities11e) — activated, end of opponent's Fight phase: D3 / 3 / D3+3 MW by D6 |
| Wazbom Blastajet | Go fer da Weak Spot | In your Shooting phase, this unit’s ranged attacks that target a MONSTER/VEHICLE unit have | not at all (the 10e 'Blastajet Attack Run' re-roll removed) | implemented (OrkAbilities11e) — +1 to wound vs MONSTER/VEHICLE in your Shooting phase |
| Wazbom Blastajet | Blastajet Force Field | Models in this unit: Have 5+ InSv.Do not have SMOKE. | partially: 10e row | re-implemented (codex mechanic; old code removed) — 5+ invuln |
| Warbikers | High-speed Carnage | If this unit made a charge move this turn, this unit’s melee attacks have: +1 S and D. | not at all | implemented (OrkAbilities11e) — charged: melee +1 S, +1 D |
| Warbuggies | Drive-by Skorchin’ | In your Movement phase, you can select one visible enemy unit (excluding MONSTER/VEHICLE u | not at all (the 10e 'Drive-by Dakka' AP rider removed) | implemented (OrkAbilities11e) — activated, start/end of move: enemy cannot be targeted by Fire Overwatch (end of turn) |
| Mek Gunz | Madcap Artillery | In your Shooting phase, when this unit has shot, if all ranged weapons equipped by each Me | not at all | implemented (OrkAbilities11e) — post-shot: wobbled / zapped / smashed / grounded by the equipped gun (MA-LOADOUT) |
| Battlewagon | Mobile Fortress | Ranged attacks that target this unit have -1 D. | not at all (the 10e 'Ramshackle but Rugged' canon name removed) | implemented (OrkAbilities11e) — -1 D vs ranged |
| Deff Dread | Dread ’Ard | Attacks that target this unit have -1 D. | not at all (the 10e 'Piston-driven Brutality' charge MW removed) | implemented (OrkAbilities11e) — -1 D vs every attack |
| Killa Kans | Spiteful Power Trip | This unit’s attacks that target a unit that has no models with a T of 7+ have +1 to hit ro | implemented as the old 10e 'Shooty Power Trip' (random self-buff) | re-implemented (codex mechanic; old code removed) — +1 to hit vs a unit with no T7+ model |
| Morkanaut | Gut Hatch | In your Movement phase, when this unit ends a normal move, units embarked within this unit | not at all | implemented (OrkAbilities11e) — activated, unit_ended_normal_move: assault-disembark follow-up |
| Morkanaut | Big an’ Shooty | In your Shooting phase, this unit’s ranged attacks can re-roll hit rolls of 1. | partially: 10e-era row | re-implemented (codex mechanic; old code removed) — your Shooting phase: re-roll hit rolls of 1 |
| Gorkanaut | Gut Hatch | In your Movement phase, when this unit ends a normal move, units embarked within this unit | not at all | implemented (OrkAbilities11e) — activated, unit_ended_normal_move: assault-disembark follow-up |
| Gorkanaut | Big an’ Stompy | This unit’s melee attacks can re-roll hit rolls of 1. | partially: 10e-era row | re-implemented (codex mechanic; old code removed) — melee re-roll hit rolls of 1 |
| Flash Gitz | Finderz Keeperz | In your Shooting phase, if any of the following apply, this unit’s ranged attacks have +1 | not at all (the 10e 'Gun-crazy Show-offs' A4 rider removed) | implemented (OrkAbilities11e) — your Shooting phase: +1 AP while it or the target is on an objective |
| Stompa | Idol of Belligerence | In your Movement phase, when a unit embarked within this unit is selected to make a disemb | not at all | implemented (OrkAbilities11e) — units disembarking in your Movement phase are riled up |
| Stompa | Waaagh! Effigy | This unit is riled up. | partially: 10e Command-phase rider | re-implemented (codex mechanic; old code removed) — the Stompa is always riled up |
| Gargantuan Squiggoth | Walking Bastion | This unit’s attacks can ignore modifiers to: BS/WS.Hit rolls. | not at all | implemented (OrkAbilities11e) — ignores hit-roll penalties (harmful modifiers only) |
| Big Mek With Shokk Attack Gun | More Dakka | This unit’s ranged attacks have: [Ignores Cover]. If this unit is riled up, [Sustained Hit | partially: 10e-era row (riled-up rider missing) | re-implemented (codex mechanic; old code removed) — ranged [IGNORES COVER]; riled up: [SUSTAINED HITS 1] |
| Big Mek With Shokk Attack Gun | Support Shokka | While this model is within 3" of a friendly Orks Infantry unit (excluding BIG MEK WITH SHO | not at all | implemented (OrkAbilities11e) — conditional Lone Operative |
| Deffkilla Wartrike | Get Back in da Race! (Once per battle round, per army) | In your Movement phase, at the start or end of this unit’s move, you can select one friend | not at all (the 10e 'Speedboss' +1 hit rider removed) | implemented (OrkAbilities11e) — activated, start/end of move; SPEED FREEKS riled up, once per battle round per army |
| Deffkilla Wartrike | Fuel-mixa Grot | This unit has +1 to advance rolls. | partially: 10e row (auto advance 6?) | re-implemented (codex mechanic; old code removed) — +1 to advance rolls |
| Zodgrod Wortsnagga | Super Runts | This unit is riled up.This unit’s Scavenged Shivs weapons have +1 A, WS and S. | partially: 10e row | re-implemented (codex mechanic; old code removed) — riled up permanently; Scavenged Shivs +1 A/WS/S |
| Beastboss | Keep Huntin’! (Once per battle round, per army) | In your Movement phase, at the start or end of this unit’s move, you can select one friend | not at all | implemented (OrkAbilities11e) — activated, start/end of move; BEAST SNAGGA riled up, once per battle round per army |
| Beastboss | Dodge Dis! | This unit’s attacks have +1 to hit rolls. | implemented as the old 10e 'Beastboss' (+1 melee hit for the led unit) | re-implemented (codex mechanic; old code removed) — +1 to hit |
| Beastboss on Squigosaur | Thundering Stampede (Aura) | Friendly Beast Snagga units within 6" of this unit have +1 to charge rolls. | not at all | implemented (OrkAbilities11e) — aura: BEAST SNAGGA +1 to charge rolls |
| Beastboss on Squigosaur | Keep Huntin’! (Once per battle round, per army) | In your Movement phase, at the start or end of this unit’s move, you can select one friend | not at all | implemented (OrkAbilities11e) — activated, start/end of move; BEAST SNAGGA riled up, once per battle round per army |
| Beastboss on Squigosaur | Boss of da Hunt | While this unit is within 3" of a friendly Beast Snagga unit (excluding MONSTER CHARACTER | not at all | implemented (OrkAbilities11e) — conditional Lone Operative |
| Painboss | Push Dat Bit Back In (Once per battle, per unit) | In your Command phase, select one friendly Beast Snagga unit within 6" of this unit. That | implemented as the old 10e 'Sawbonez' (heal a BEAST SNAGGA character) | re-implemented (codex mechanic; old code removed) — activated, battle_shock_step_start; BEAST SNAGGA unit heals 3, once per battle |
| Painboss | Hardy Bioniks | Attacks that target this unit with a S greater than this unit’s T have -1 to wound rolls. | not at all | implemented (OrkAbilities11e) — -1 to wound when S > T |
| Painboss | Runnin’ wiv da Herd | While this model is attached to a Mounted unit, this model: Does not have INFANTRY.Has MOB | not at all | implemented (OrkAbilities11e) — +4" M while attached to MOUNTED; the keyword swap is NOT implemented |
| Mozrog Skragbad | One Last Kill | In the Fight phase, when this model is destroyed, if this unit has not been selected to fi | partially: a 10e row under the same name | re-implemented (codex mechanic; old code removed) — Fight On Death on a 2+ (OrkCodexFight marker) |
| Mozrog Skragbad | Da Bigger Dey Iz… | This unit’s melee attacks that target a MONSTER/VEHICLE unit can re-roll wound rolls. | not at all | implemented (OrkAbilities11e) — melee re-roll the wound roll vs MONSTER/VEHICLE |
| Mozrog Skragbad | Beast Snagga Following | While this unit is within 3" of a friendly Beast Snagga unit (excluding MONSTER CHARACTER | not at all | implemented (OrkAbilities11e) — conditional Lone Operative |
| Beast Snagga Boyz | Mobbed | When this unit ends a charge move, each enemy MONSTER/VEHICLE unit engaged with this unit | not at all (the 10e 'Monster Hunters' re-roll removed) | implemented (OrkAbilities11e) — after a charge: engaged MONSTER/VEHICLE battle-shock roll -1 (-2 with 13+) |
| Squighog Boyz | Bomb Squig (Once per battle, per unit) | In your Movement phase, when this unit ends a normal move, you can select one visible enem | implemented as the 10e 'Bomb Squigs' rider | re-implemented (codex mechanic; old code removed) — activated, unit_ended_normal_move; once per battle |
| Squighog Boyz | Brutal Impact | If this unit made a charge move this turn, this unit’s attacks have +1 D. | not at all (the 10e 'Wild Ride' removed) | implemented (OrkAbilities11e) — charged: melee +1 D |
| Kill Rig | Wurrboy (psyker level 1) | This model has the psychic abilities listed in the Psychic Abilities section. | partially: 10e row | re-implemented (codex mechanic; old code removed) — selects the Kill Rig's Warpath mode ([LETHAL HITS]) |
| Hunta Rig | Fully Loaded Butchery | This unit’s Butcha Boyz weapon has +2 A for each model embarked within this unit (to a max | implemented as the old 10e 'On Da Hunt' (+1 A per embarked model, max 6) | re-implemented (codex mechanic; old code removed) — Butcha Boyz +2 A per embarked model |
| Hunta Rig | Tramplasquig Charge | When you target this unit with the Crushing Impact stratagem, that use is -1 CP. | not at all | implemented (OrkAbilities11e) — Crushing Impact on the Hunta Rig costs 1 CP less |
| Big’ed Bossbunka | Raucous Occupants | While this model is within range of your home objective, add the OC of models embarked wit | not at all | NOT implemented — Big'ed Bossbunka fortification trio — no fortification rules engine |
| Big’ed Bossbunka | Fortification | While an enemy unit is engaged with only FORTIFICATION units: That enemy unit can be selec | partially (generic fortification flag) | NOT implemented — Big'ed Bossbunka — core fortification handling is another package |
| Big’ed Bossbunka | Ramshackle Cover | When an attack targets a unit that is not fully visible to the attacking model because of | not at all | NOT implemented — Big'ed Bossbunka — no fortification cover engine |
| Big Mek | More Dakka | This unit’s ranged attacks have: [Ignores Cover].If this unit is riled up, [Sustained Hits | partially: 10e-era row (riled-up rider missing) | re-implemented (codex mechanic; old code removed) — ranged [IGNORES COVER]; riled up: [SUSTAINED HITS 1] |
| Big Mek | Shokk-boosta | In your Movement phase, when this unit is selected to make an advance move, you can use th | not at all | implemented (OrkAbilities11e) — activated, selected to advance: advance roll 6, moves through models, hazard rolls at the end |
| Breaka Boyz | Bomb Squigs (Once per turn, twice per battle, per unit) | In your Movement phase, when this unit ends a normal move, you can select one visible enem | implemented with the 10e text (once per battle) | re-implemented (codex mechanic; old code removed) — activated, unit_ended_normal_move; once per turn, twice per battle |
| Breaka Boyz | Trophy Hunters | This unit has +1 to charge rolls. | not at all | implemented (OrkAbilities11e) — +1 to charge rolls |
| Wazdakka Gutsmek | Full Throttle | In your Command phase, select one Throttlerokkit Shokka Engine ability (see above). This u | partially: 10e Turbo-boost rows | re-implemented (codex mechanic; old code removed) — activated, battle_shock_step_start: choose an engine until your next Command phase |
| Bannernob | Waaagh! Banner | This unit has +1 to charge rolls. | partially: 10e Waaagh! rider | re-implemented (codex mechanic; old code removed) — +1 to charge rolls |
| Bigboss | Sumfin’ to Prove | This unit’s melee attacks have +1 to hit rolls. | not at all | implemented (OrkAbilities11e) — melee +1 to hit |
| Big Mek Dakkarig | Even More Dakka | If this unit is riled up, this unit’s ranged attacks have [Sustained Hits 1]. | not at all | implemented (OrkAbilities11e) — riled up: ranged [SUSTAINED HITS 1] |
| Big Mek Dakkarig | Blitz Dem Gitz! | In your Shooting phase, if this unit’s Blitzkannon weapon targets a unit (excluding MONSTE | not at all | implemented (OrkAbilities11e) — blitzkannon +6 A vs non-MONSTER/VEHICLE |
| Runtherd | That’ll Learn Ya (Once per battle round, per unit) | When this unit becomes battle-shocked, if this unit contains 4+ Gretchin models, you can r | not at all (the 10e 'Runtherd' T2 rider removed) | implemented (OrkAbilities11e) — activated, unit_battle_shocked: D3 Gretchin destroyed, no longer battle-shocked; once per battle round |
| Wartrakks | Speednob Support | While each model in this unit is within 3" of a friendly Speed Freeks unit (excluding WART | not at all | implemented (OrkAbilities11e) — conditional Lone Operative (each model within 3" of SPEED FREEKS) |
| Wartrakks | Bust ’Em | In your Shooting phase, when this unit has shot, select one enemy unit hit by those attack | not at all | implemented (OrkAbilities11e) — post-shot: friendly SPEED FREEKS [LETHAL HITS] vs the unit until end of turn |
| Gunwagon | Mobile Arsenal | In your Shooting phase, this unit’s ranged attacks can re-roll hit rolls of 1. | not at all | implemented (OrkAbilities11e) — your Shooting phase: re-roll hit rolls of 1 |
| Nazdreg | Intimidating Motivation (Once per battle round, per army) | In your Movement phase, at the start or end of this unit’s move, you can select one friend | not at all | implemented (OrkAbilities11e) — activated, start/end of move; once per battle round per army |
| Nazdreg | Nazdreg’s Know-wotz | This unit has Deep Strike.This unit’s ranged attacks have [Ignores Cover]. | not at all | implemented (OrkAbilities11e) — ranged [IGNORES COVER] |
| Nazdreg | Supreme Kunnin’ (Once per phase, per army) | In your opponent’s Movement phase, when an enemy unit ends a move within 8" of this unit, | not at all | implemented (OrkAbilities11e) — activated, enemy_ended_move within 8": reactive normal move D6" (5" riled up) |
| Rukkatrukk Squigbuggies | Squig Barrage | In your Shooting phase, when this unit has shot, select one enemy unit (excluding MONSTER/ | not at all | implemented (OrkAbilities11e) — post-shot: hit unit's attacks -1 to hit until your next turn (approximated as 'hit by this unit') |
| Weirdboy | Da Jump (psychic level 1, once per army, per battle round) | Psychic roll; place this unit in strategic reserves; it has Deep Strike. | partially: 10e 'Da Jump (Psychic)' teleport dialog | re-implemented (codex mechanic; old code removed) — activated psychic, movement_phase_start/end: strategic reserves + Deep Strike, once per army per round |
| Weirdboy | Warpath (psychic level 1) | When selected to fight: psychic roll; melee attacks re-roll wound rolls of 1, [PSYCHIC]. | not at all | implemented (OrkAbilities11e) — activated psychic, unit_selected_to_fight: Weirdboy re-roll wounds of 1 / Kill Rig [LETHAL HITS], +[PSYCHIC] |
| Kill Rig | Beastscent (psychic level 1) | When a unit embarked within it disembarks: psychic roll; +1 to wound vs MONSTER/VEHICLE. | not at all | implemented (OrkAbilities11e) — psychic, when a unit disembarks: +1 to wound vs MONSTER/VEHICLE until end of turn (auto-used when the psychic budget allows) |
| Kill Rig | Warpath (psychic level 1) | When selected to fight: psychic roll; melee [LETHAL HITS], [PSYCHIC]. | not at all | implemented (OrkAbilities11e) — activated psychic, unit_selected_to_fight: Weirdboy re-roll wounds of 1 / Kill Rig [LETHAL HITS], +[PSYCHIC] |
| Wazdakka Gutsmek | Turbo Engine | Advance / fall-back move does not prevent declaring a charge. | partially: 10e rows | re-implemented (codex mechanic; old code removed) — Full Throttle option: advance / fall back and still charge |
| Wazdakka Gutsmek | Shokk Attack Engine | Command phase, unengaged: place this unit in strategic reserves. | not at all | implemented (OrkAbilities11e) — activated (after Full Throttle 'shokk'): unengaged -> strategic reserves |
| Wazdakka Gutsmek | Pulse Jet | Movement phase, selected to move, unengaged: make a pulse jet move. | not at all | NOT implemented — selectable in Full Throttle but the pulse jet move does nothing yet |

## Counts per action

- implemented (OrkAbilities11e): 62
- re-implemented (codex mechanic; old code removed): 37
- NOT implemented: 6
- other package: 1
- re-keyed (same mechanic, codex name): 1

## The 33 game-dispatched 10e names the codex dropped

Every one is gone from `UnitAbilityManager.ABILITY_EFFECTS` / phase dispatch / AI listeners (pinned by `tests/test_ork_abilities_11e.gd` section 29), except 'Tank Hunters' whose row stays for Death Guard:

- Ammo Runt — re-implemented as Ammo Runts / Boss' Ammo Runt
- Beastboss — removed; the Beastboss datasheet now has Keep Huntin'! / Dodge Dis!
- Blastajet Attack Run — removed; Go fer da Weak Spot
- Clankin' Forward — removed; Spiteful Power Trip
- Da Biggest and da Best — removed; Might Is Right
- Da Boss' Ladz — removed; Da Grand Warlord's Ladz
- Dead Brutal — removed; Krushin' Impetus
- Distraction Grot — removed with its dialog flow; no codex equivalent
- Dok's Toolz — removed; Crude Surgery
- Drive-by Dakka — removed; Drive-by Skorchin'
- Get Da Good Bitz — removed; Thievin' Scavengers
- Grot Oiler — removed; Fix Dat Armour Up
- Grot Orderly — removed; Catch Dat Red Bit
- Grot Riggers — removed; no codex equivalent
- Gun-crazy Show-offs — removed; Finderz Keeperz
- Hold Still and Say 'Aargh!' — removed; Push Dat Bit Back In
- Mekaniak — removed; Clever Know-wotz
- Monster Hunters — removed; Mobbed
- On Da Hunt — removed; Thundering Stampede
- Patrol Squad — re-keyed to Taktikal Know-wotz (same split mechanic)
- Piston-driven Brutality — removed; Dread 'Ard
- Ramshackle but Rugged — removed (and its ABILITY_NAME_CANON entry); Mobile Fortress
- Red Skull Kommandos — removed; Kunnin' Infiltrator
- Runtherd — removed; That'll Learn Ya
- Sawbonez — removed; Crude Surgery
- Shooty Power Trip — removed; Spiteful Power Trip
- Special Dose — removed; no codex equivalent
- Speedboss — removed; Get Back in da Race!
- Spirit of Gork (Psychic) — removed (canon keeps only 'Da Jump (Psychic)')
- Splat! — removed; One Last Kill
- Stompin' Forward — removed; Big an' Stompy
- Tank Hunters — Ork dispatch removed; the ABILITY_EFFECTS row stays (Death Guard uses it); Rokkit Barrage
- Wild Ride — removed; Brutal Impact
