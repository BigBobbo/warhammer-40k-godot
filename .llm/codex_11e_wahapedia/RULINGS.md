# Codex 11e rulings (one line each, per work package)

Rulings made while implementing ambiguous printed text. Format:
`- <rule>: <ruling> (<why>)`

## Data import (W / C1 / O1)
- Ork curated stratagems vs the 2026-10-16 export: identical text; Wahapedia's phase column for MOW 'EM DOWN and UNBRIDLED CARNAGE reads "Charge or Fight phase" while WHEN says "Fight phase, when ... selected to fight" — kept "Fight phase" (the WHEN governs use).
- Praesidium Shield: no stat bonus (codex: -1 D to attacks allocated to the bearer — WP-C7).
- Vexilla: +1 OC applies only to units whose roster took a Vexilla (wargear abilities are emitted only for wargear the roster lists).
- Units sold in fixed sizes are snapped to a printed size (Gretchin 11 -> 10); pre-codex Custodes model counts are clamped (Custodian Guard 4-5 -> Sodality 3).
- Legends datasheets (Lootas, Burna Boyz, Aleya, Valerian, ...) are not imported; roster entries for them are kept unchanged (owner decision D2).

## WP-C3

## WP-C5

## WP-C46

## WP-C7

## WP-O34
- Waaagh! "can re-roll advance rolls": offered as an optional FREE re-roll in the advance re-roll dialog (in place of the Command Re-roll prompt for that roll); not offered for a 6, for a roll another rule changed (Thundering Wagons, Unstoppable Momentum), or when another ability already grants the unit an advance re-roll; the whole Attached unit counts (an attached Warboss lends it); AI re-rolls a 1-3 (expected value 3.5).
- Waaagh! free re-roll and the opponent's-Command-phase War Cry window are not offered while a tutorial lesson runs (the T3 lesson teaches Command Re-roll; lessons keep their scripted flow, like stratagem windows).
- War Cry "at the start of the Command phase" is not "your": in the Ork player's own Command phase it is the existing CALL DA WAAAGH! button; in the opponent's Command phase it is a free rule window for the Ork player at that phase's first decision point (the Battle-shock step start, before any roll).
- War Cry "until the end of the next turn": the turn after the one whose Command phase it was used in (used in your own Command phase -> lasts through the opponent's turn; used in the opponent's -> lasts through your next turn); expiry is checked at the start of every Command phase; a pre-WP-O34 save with an active Waaagh! and no recorded expiry keeps the old end (its owner's next Command phase).
- Riled up keeps the PR #917 flags (5+ InSv, ranged [ASSAULT], advance-and-charge); 11e has no +1 S/A.
- Da Boss: "start of the battle round" = the first-turn player's Command phase entry (where the engine resets per-round state); the WARLORD must be alive (battlefield, embarked or reserves); once per battle round per player (recorded); not limited by the engine's 10e "1 bonus CP per battle round" cap (no such cap in 11e).
- Unstable Energies: psyker level comes from the unit's psyker-level ability (Waaagh! Energy / Wurrboy = 1; the army files drop the printed "(psyker level N)" suffix, a suffix that is present wins; other packages may raise it via flags.ork11e_psyker_level); a budgeted ORKS PSYKER without a listed level counts as level 1.
- Unstable Energies: psychic level = the "(psychic level N)" in the ability name, 1 when absent; the budget is per PSYKER unit per battle round (the unit carrying the ability — an attached Weirdboy keeps its own budget); 22.03.01 the same psychic ability once per phase.
- Unstable Energies enforcement: Da Jump, Roar of Mork and Visions of Violence check the budget; an over-budget ability is not offered (Da Jump disappears from the action list, the rule windows drop it) and the player gets one Game Log line + toast per unit/ability/phase naming the budget.
- Rule choices (War Cry in the opponent's phase, Try Dat Button!, Hop Splat, Roar of Mork, Visions of Violence) ride the stratagem-window framework as FREE "rule offers" listed first; using one re-offers the window so its stratagems remain available (a rule choice is not a stratagem use); they cost no CP and never count as a stratagem for 15.01 / once-per-phase limits.
- Detachment keyword checks look at the whole Attached unit (19.03): an attached Warboss/character makes the unit a WARBOSS/ORKS/... unit for Get Stuck In, Displays of Savagery, Da Hunt is On, etc.
- BATTLELINE grants (Kult of Speed Warbikers, Taktikal Brigade Stormboyz, Runt Swarm Gretchin) are written into meta.keywords when the army is applied and refreshed at each of the owner's Command phases — every BATTLELINE reader (stratagem targeting, the AI) sees them; the 10e Dread Mob Gretchin grant is gone at 11e.
- Sustained Hits from Get Stuck In / Displays of Savagery / Mob-handed Brutality do not stack with each other or with a weapon's own [SUSTAINED HITS] (a weapon that has its own keeps it); [LETHAL HITS] likewise is not doubled.
- Mob-handed Brutality [LETHAL HITS: non-MONSTER/VEHICLE]: only vs targets with neither keyword; "made a charge move this turn" = flags.charged_this_turn.
- Da Hunt is On: +1 AP on every attack (ranged and melee, all resolver paths) by a Beast Snagga unit vs an enemy MONSTER/VEHICLE unit; it replaces the 10e Prey rule (no Prey selection, no Prey charge re-roll at 11e).
- Adrenaline Junkies: [ASSAULT] "until the end of the turn" after an advance/fall-back move; advance/fall back never prevents declaring a charge; falling back still forbids shooting (09.07 — [ASSAULT] lifts only the advance restriction).
- Suspiciously Well Organised: fall-back-and-charge only (an advance still prevents the charge); the 10e Lissen 'Ere Taktiks are not offered at 11e.
- Unstoppable Momentum: the WAGON advance roll is always changed to a 6 (the roll is a maximum, so "can" never hurts); a changed roll is not re-rolled; the charge re-roll is the free ability re-roll dialog; the 10e Eager for the Fight advance re-roll is off at 11e.
- Wreckin' and Lootin': your Shooting phase only (not Overwatch); "within range of an objective" uses the objective-control predicate; checked per attack target.
- Sneaky Little Gitz: the advance/fall-back move does not set the unit's 16.01 action lock (same mechanism as MIND MOSTLY ON THE MISSION).
- Dakka! Dakka! Dakka!: [ASSAULT] for every ORKS INFANTRY ranged weapon; +3" Range while riled up changes the Range characteristic (half range follows); the range circles drawn on the board do not show the +3".
- Skyborne Loons: an AIRCRAFT unit's points count 0 towards the strategic-reserves points limit (Formations declaration, Deployment reserves, GameState.get_reserves_points); +1 to hit for ranged attacks only, while riled up.
- Unpredictable Genius: rolled once per shooting when all of the unit's ranged attacks target one enemy unit (split fire: no roll), in your Shooting phase only; results last "until your unit has shot" (cleared after its attacks, and at the end of the phase); Lifted grants FLY only if the target lacked it and denies cover to this shooter's attacks.
- Hop Splat: with two or more other enemy units within 3" of the target the player picks in a rule window (decline = the closest); one candidate is hit automatically; the AI picks the unit where D3 mortal wounds cost the most (points per model / wounds left); D3 mortal wounds go to the bodyguard first, then attached characters.
- Try Dat Button!: offered when an ORKS WALKER (not TITANIC) is selected to shoot in your Shooting phase or to fight in either Fight phase, as two variants (one D6 / two D6, no "plain" use); "keep re-rolling duplicate results" = re-roll until the two dice land on different table rows (two identical rules would add nothing); effects end when the unit has attacked; with two dice one hazard roll is made then; a unit that never attacks makes no hazard roll. AI always uses it, rolling two dice only with 8+ wounds left in the unit (a failed hazard roll costs a VEHICLE 3 mortal wounds).
- 'Ard as Nails: only for a WARBOSS model destroyed in the Fight phase (the Fight On Death machinery of ORKS IS NEVER BEATEN); not if its unit was already selected to fight this phase; pass on 3+ (+1 riled up); kept models are removed when the unit has fought or at the end of the phase.
- Powers of da Waaagh!: +1 S, +1 S per 5 models in the unit (alive models of the Attached unit + embarked models) on [PSYCHIC] weapons of ORKS PSYKER units; Roar of Mork (your Movement phase end window) and Visions of Violence (start of the Fight phase window, before Pile In, for both players' Wurrband psykers) are psychic level 1 abilities under Unstable Energies.
- Roar of Mork target: an enemy unit (excluding MONSTER/VEHICLE, attached characters folded into their unit) within 12" of the psyker's Attached unit; -1 to the battle-shock roll per 10 models in the psyker's unit; battle-shock-immune targets are reported and unaffected.
- Visions of Violence: Fights First until the end of the Fight phase (cleared then unless the unit already had it); the psychic roll's 1 battle-shocks the psyker but Fights First still applies.

## WP-O5

## WP-O6
