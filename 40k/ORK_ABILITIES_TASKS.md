# Orks Freebooter Krew — Ability Audit Tasks

> Source: Full ability audit of Orks faction (Freebooter Krew detachment)
> Goal: Implement all missing unit abilities, detachment rules, enhancements, and stratagems for Orks Freebooter Krew army.
> Generated: 2026-03-09

---

## Phase 1: Core/Faction Abilities

### OA-1: Implement "Here Be Loot" detachment ability
- [x] Add "Freebooter Krew" entry to `FactionAbilityManager.DETACHMENT_ABILITIES`
- [x] Implement loot objective selection prompt at start of each battle round (before Command phase)
- [x] Track which objective marker is the current loot objective
- [x] Apply Sustained Hits 1 to all Orks Infantry/Mounted/Walker units within range of loot objective
- [x] Apply Sustained Hits 1 to all attacks targeting units within range of loot objective
- [x] Reset loot objective each battle round
- [x] Add UI indicator showing which objective is the loot objective
- **Files**: FactionAbilityManager.gd, CommandPhase.gd, RulesEngine.gd, Main.gd, new loot objective selection dialog
- **Validation**: At battle round start, player selects loot objective. Orks Infantry/Mounted/Walker units near it get Sustained Hits 1. Attacks targeting units near it also get Sustained Hits 1. Resets each round. Works for local and cloud-loaded armies.

### OA-2: Register Freebooter Krew enhancements
- [x] Define all 4 enhancement abilities: Da Kaptin, Git-spotter Squig, Bionik Workshop, Razgit's Magik Map
- [x] Da Kaptin (10pts, Warboss only): start of any phase, select Battle-shocked friendly ORKS unit within 12" — D3 mortal wounds, no longer Battle-shocked. Once per battle round
- [x] Git-spotter Squig (20pts, ORKS model): bearer's unit ranged weapons gain Ignores Cover
- [x] Bionik Workshop (15pts, Big Mek or Painboy): at start of battle, roll D3 for random bionik — adds Move, Strength, or WS bonus to bearer's unit
- [x] Razgit's Magik Map (25pts, ORKS model): after deployment, redeploy up to 3 Orks Infantry units (can go to Strategic Reserves)
- [x] Wire enhancement effects into correct phase triggers
- **Files**: UnitAbilityManager.gd, FactionAbilityManager.gd, CommandPhase.gd, DeploymentPhase.gd
- **Validation**: Each enhancement applies correctly when equipped on valid models. Once-per-round tracking for Da Kaptin. Random roll for Bionik Workshop at battle start. Razgit's Magik Map allows redeployment.

### OA-3: Implement "Bash and Grab" stratagem
- [x] Ensure Freebooter Krew detachment is registered so stratagems load from CSV
- [x] Implement Fight phase stratagem: 1 CP, target one ORKS unit that hasn't fought
- [x] Apply re-roll Wound rolls for attacks targeting enemies within range of loot objective
- [x] Enforce once-per-phase restriction
- **Files**: FactionAbilityManager.gd, StratagemManager.gd, FactionStratagemLoader.gd
- **Validation**: Stratagem appears during Fight phase. Re-roll Wound rolls only vs targets within range of loot objective. 1 CP deducted. Once-per-phase enforced.

### OA-4: Implement "Grab and Bash" stratagem
- [x] Implement Command phase stratagem: 1 CP, target one non-Gretchin Orks unit within range of loot objective
- [x] Apply per-unit Waaagh! effects (5+ invuln, +1S/A melee, advance+charge) to targeted unit only
- [x] Effects last until start of next Command phase
- [x] Works even if Waaagh! has already been called this battle
- **Files**: StratagemManager.gd, FactionAbilityManager.gd
- **Validation**: Available during Command phase. Only targets non-Gretchin ORKS units near loot objective. Waaagh! effects apply to targeted unit. Lasts until next Command phase.

### OA-5: Implement "Boardin' Rush" stratagem
- [x] Implement Movement phase stratagem: 1 CP, target one ORKS unit that hasn't moved
- [x] When unit Advances, skip roll and add flat 6" to Move instead
- [x] Only affects targeted unit for current phase
- **Files**: StratagemManager.gd, MovementPhase.gd, MovementController.gd
- **Validation**: Available during Movement phase before unit moves. Advance roll skipped, +6" added to Move. Only affects targeted unit.

### OA-6: Implement "Rolling Loot-heap" stratagem
- [x] Implement Shooting phase stratagem: 1 CP, target one Flash Gitz unit that hasn't shot
- [x] Grant Anti-Vehicle 4+ to all ranged weapons until end of phase
- [x] Validate only Flash Gitz units can be targeted
- **Files**: StratagemManager.gd, RulesEngine.gd
- **Validation**: Only targets Flash Gitz. Grants Anti-Vehicle 4+. Critical wounds on 4+ against VEHICLE keyword units.

### OA-7: Implement "Deck Fraggers" stratagem
- [x] Implement Shooting phase stratagem: 1 CP, target one ORKS unit that hasn't shot
- [x] Grant BLAST keyword to ranged weapons only when targeting INFANTRY units
- [x] BLAST bonus attacks calculated correctly (min 3 if 6+ models in target)
- **Files**: StratagemManager.gd, RulesEngine.gd
- **Validation**: Available during Shooting phase. BLAST added only when targeting INFANTRY. Bonus attacks correct.

### OA-8: Implement "Krump and Run" stratagem
- [x] Implement reactive stratagem: opponent's Movement phase, 1 CP
- [x] Trigger after enemy unit falls back from engagement with targeted ORKS unit
- [x] ORKS unit must not be engaged with other enemies
- [x] Allow up to 6" Normal move for freed Ork unit
- **Files**: StratagemManager.gd, MovementPhase.gd, MovementController.gd
- **Validation**: Triggers after enemy falls back. ORKS unit not engaged with others. Up to 6" Normal move. Opponent's turn timing enforced.

---

## Phase 2: Combat Abilities

### OA-9: Implement "Gun-crazy Show-offs" ability for Flash Gitz
- [x] Add "Gun-crazy Show-offs" to UnitAbilityManager.ABILITY_EFFECTS
- [x] When targeting closest eligible enemy, snazzgun Attacks = 4
- [x] When targeting non-closest enemies, snazzgun Attacks = 3 (base)
- [x] Implement closest-target validation using model-to-model distance
- **Files**: UnitAbilityManager.gd, RulesEngine.gd, ShootingPhase.gd
- **Validation**: Snazzgun Attacks = 4 vs closest enemy. Attacks = 3 vs non-closest. Distance calculated correctly.

### OA-10: Implement "Ammo Runt" wargear ability for Nobz and Flash Gitz
- [x] Add "Ammo Runt" to UnitAbilityManager.ABILITY_EFFECTS with once-per-battle tracking
- [x] When unit selected to shoot, prompt "Use Ammo Runt?"
- [x] Grant Lethal Hits to all ranged weapons for the phase
- [x] Track multiple ammo runts independently (Nobz can have 2)
- **Files**: UnitAbilityManager.gd, ShootingPhase.gd, RulesEngine.gd
- **Validation**: Once-per-battle per ammo runt. Lethal Hits granted. UI prompt shown. Multiple runts tracked independently.

### OA-11: Implement "Tank Hunters" ability for Tankbustas
- [x] Add "Tank Hunters" to UnitAbilityManager.ABILITY_EFFECTS with target-keyword condition
- [x] Apply +1 to Hit roll when attacking MONSTER or VEHICLE targets
- [x] Apply +1 to Wound roll when attacking MONSTER or VEHICLE targets
- [x] No bonus when attacking other unit types
- **Files**: UnitAbilityManager.gd, RulesEngine.gd
- **Validation**: +1 Hit and +1 Wound vs MONSTER/VEHICLE. No bonus vs other types. Applies to all ranged attacks.

### OA-12: Implement "Dat's Our Loot!" ability for Lootas
- [x] Add "Dat's Our Loot!" to UnitAbilityManager.ABILITY_EFFECTS
- [x] Re-roll Hit rolls of 1 on all ranged attacks
- [x] Full Hit re-roll when target is within range of an objective marker
- [x] Objective proximity check uses correct range calculation
- **Files**: UnitAbilityManager.gd, RulesEngine.gd
- **Validation**: Re-roll 1s on all ranged attacks. Full re-roll vs targets on objectives. Range check correct.

### OA-13: Implement "Drive-by Dakka" ability for Warbikers and Wartrakks
- [x] Add "Drive-by Dakka" to UnitAbilityManager.ABILITY_EFFECTS
- [x] Improve AP by 1 for ranged attacks against targets within 9"
- [x] No AP improvement for targets beyond 9"
- [x] Applies to both Warbikers and Wartrakks
- **Files**: UnitAbilityManager.gd, RulesEngine.gd
- **Validation**: AP improved by 1 vs targets within 9". No improvement beyond 9". Works for both units.

### OA-14: Implement "Pyromaniaks" ability for Burna Boyz and Skorchas
- [ ] Add "Pyromaniaks" to UnitAbilityManager.ABILITY_EFFECTS
- [ ] Re-roll Wound rolls of 1 with burna/Torrent weapons vs enemies within 6"
- [ ] Full Wound re-roll when target is also within range of an objective marker
- **Files**: UnitAbilityManager.gd, RulesEngine.gd
- **Validation**: Re-roll wound 1s vs enemies within 6" with Torrent weapons. Full re-roll if also on objective.

### OA-15: Implement "Da Boss' Ladz" ability for Nobz
- [x] Add "Da Boss' Ladz" to UnitAbilityManager.ABILITY_EFFECTS
- [x] Apply -1 to incoming Wound rolls when attack Strength > unit Toughness
- [x] Only active when a Warboss model is leading the Nobz unit
- [x] No effect when S <= T or no Warboss attached
- **Files**: UnitAbilityManager.gd, RulesEngine.gd
- **Validation**: -1 Wound roll when S > T and Warboss leads. No effect when S <= T or no Warboss.

### OA-16: Implement "Dakkastorm" ability for Dakkajet
- [x] Add "Dakkastorm" to UnitAbilityManager.ABILITY_EFFECTS
- [x] Every successful Hit roll scores a Critical Hit for ranged attacks
- [x] Sustained Hits and Lethal Hits trigger on every successful hit
- [x] Only applies to ranged attacks, not melee
- **Files**: UnitAbilityManager.gd, RulesEngine.gd
- **Validation**: All successful Hit rolls are Critical Hits. Sustained/Lethal Hits trigger on every hit. Ranged only.

### OA-17: Implement "Krumpin' Time" ability for Meganobz
- [x] Add "Krumpin' Time" to UnitAbilityManager.ABILITY_EFFECTS with waaagh_active condition
- [x] Apply FNP 5+ when Waaagh! is active
- [x] Remove FNP 5+ when Waaagh! deactivates
- [x] Does not stack with other FNP sources (use better value)
- **Files**: UnitAbilityManager.gd, FactionAbilityManager.gd
- **Validation**: FNP 5+ when Waaagh! active. No FNP when inactive. No stacking.

### OA-18: Implement "Kustom Force Field" wargear for Big Mek
- [ ] Add "Kustom Force Field" to UnitAbilityManager.ABILITY_EFFECTS (condition: while_leading)
- [ ] Grant 4+ invulnerable save to led unit against ranged attacks only
- [ ] Does not apply in melee
- [ ] Only active when Big Mek is alive and attached as leader
- **Files**: UnitAbilityManager.gd, RulesEngine.gd
- **Validation**: 4+ invuln vs ranged attacks. No invuln in melee. Only when Big Mek leads.

### OA-19: Implement "Hold Still and Say 'Aargh!'" ability for Painboy
- [ ] Add ability to UnitAbilityManager.ABILITY_EFFECTS
- [ ] On Critical Wound with 'urty syringe, target suffers D6 mortal wounds
- [ ] Exclude VEHICLE targets from mortal wound effect
- [ ] Only applies to 'urty syringe weapon, not all Painboy attacks
- **Files**: UnitAbilityManager.gd, RulesEngine.gd
- **Validation**: D6 mortal wounds on Crit Wound with 'urty syringe. No mortals vs VEHICLE. Weapon-specific.

### OA-20: Implement "Prophet of Da Great Waaagh!" Crit Hit on 5+ for Ghazghkull
- [ ] Extend existing "Prophet of Da Great Waaagh!" definition (already has +1 Hit/+1 Wound)
- [ ] Add Critical Hit on unmodified 5+ when Waaagh! is active
- [ ] Both +1 Hit/Wound and Crit 5+ apply simultaneously during Waaagh!
- **Files**: UnitAbilityManager.gd, RulesEngine.gd
- **Validation**: +1 Hit and +1 Wound always active while leading. Crit Hit threshold 5+ during Waaagh!. Both effects stack.

---

## Phase 3: Movement/Positioning Abilities

### OA-21: Implement "Full Throttle" ability for Stormboyz
- [ ] Add "Full Throttle" to UnitAbilityManager.ABILITY_EFFECTS
- [ ] Allow unit to charge after Advancing
- [ ] Allow unit to charge after Falling Back
- **Files**: UnitAbilityManager.gd, ChargePhase.gd
- **Validation**: Unit can charge after Advancing. Unit can charge after Falling Back.

### OA-22: Implement "High-octane Fuel" ability for Warboss On Warbike
- [ ] Add "High-octane Fuel" to UnitAbilityManager.ABILITY_EFFECTS
- [ ] Replace Advance roll with flat +6" to Move when leading a unit
- **Files**: UnitAbilityManager.gd, MovementPhase.gd
- **Validation**: No Advance roll. Move +6" when Advancing. Only for units led by Warboss On Warbike.

### OA-23: Implement "Plummeting Descent" ability for Boss Zagstruk
- [ ] Add "Plummeting Descent" to UnitAbilityManager.ABILITY_EFFECTS
- [ ] Allow charge roll re-rolls when unit was set up from Reserves this turn
- [ ] No re-roll benefit on subsequent turns
- **Files**: UnitAbilityManager.gd, ChargePhase.gd
- **Validation**: Charge re-rolls available when arriving from Reserves. No re-roll later turns.

### OA-24: Implement "Kunnin' Infiltrator" ability for Boss Snikrot
- [ ] Add "Kunnin' Infiltrator" to UnitAbilityManager.ABILITY_EFFECTS
- [ ] Once per battle, in Movement phase, remove unit and redeploy 9"+ from all enemies
- [ ] Track once-per-battle usage
- [ ] Add UI for redeployment placement
- **Files**: UnitAbilityManager.gd, MovementPhase.gd, MovementController.gd
- **Validation**: Once per battle teleport. Must be 9"+ from enemies. Usage tracked.

### OA-25: Implement "Deff from Above" ability for Deffkoptas
- [ ] Add "Deff from Above" to UnitAbilityManager.ABILITY_EFFECTS
- [ ] After Normal move, select one enemy unit moved over
- [ ] Roll D6 per model in unit, 4+ = 1 mortal wound
- [ ] Only triggers on Normal moves (not Advance, Fall Back, etc.)
- **Files**: UnitAbilityManager.gd, MovementPhase.gd
- **Validation**: After Normal move, select enemy moved over. D6 per model, 4+ = 1 MW. Normal moves only.

### OA-26: Implement "Drive-by Krumpin'" ability for Nobz On Warbikes
- [ ] Add "Drive-by Krumpin'" to UnitAbilityManager.ABILITY_EFFECTS
- [ ] Override Consolidation distance to 6" instead of 3"
- **Files**: UnitAbilityManager.gd, FightPhase.gd
- **Validation**: Consolidation move is 6" instead of 3".

### OA-27: Implement "Outflank" ability for Warbuggies
- [ ] Add "Outflank" to UnitAbilityManager.ABILITY_EFFECTS
- [ ] Allow deployment in opponent's deployment zone when arriving from Strategic Reserves
- [ ] Other reserve restrictions still apply
- **Files**: UnitAbilityManager.gd, MovementPhase.gd
- **Validation**: Can deploy in opponent's zone from Strategic Reserves. Other restrictions apply.

### OA-28: Implement "Clankin' Forward" ability for Morkanaut/Gorkanaut
- [ ] Add "Clankin' Forward" to UnitAbilityManager.ABILITY_EFFECTS
- [ ] Allow moving over non-MONSTER/VEHICLE enemy models
- [ ] Allow moving over terrain 4" or less in height
- **Files**: UnitAbilityManager.gd, MovementPhase.gd
- **Validation**: Can move over non-MONSTER/VEHICLE enemies and terrain ≤4".

### OA-29: Implement "Stompin' Forward" ability for Stompa
- [ ] Add "Stompin' Forward" to UnitAbilityManager.ABILITY_EFFECTS
- [ ] Allow moving over all non-TITANIC models
- [ ] Allow moving over terrain 4" or less in height
- **Files**: UnitAbilityManager.gd, MovementPhase.gd
- **Validation**: Can move over all non-TITANIC models and terrain ≤4".

---

## Phase 4: Situational/Conditional Abilities

### OA-30: Implement "Bomb Squigs" (multi-squig) for Tankbustas
- [ ] Extend existing Bomb Squig implementation to support Tankbustas (2 squigs vs Kommandos 1)
- [ ] Once per battle per squig, after Normal move, enemy within 12": on 3+, D3 mortal wounds
- [ ] Track per-squig usage independently
- **Files**: UnitAbilityManager.gd
- **Validation**: 2 squigs tracked independently. Each triggers once per battle. D3 MW on 3+.

### OA-31: Implement "Pulsa Rokkit" wargear for Tankbustas
- [ ] Add once-per-battle wargear ability
- [ ] When unit shoots: +1 S and +1 AP to all ranged weapons for the phase
- **Files**: UnitAbilityManager.gd, ShootingPhase.gd
- **Validation**: Once per battle. +1S and +1AP to ranged weapons for phase.

### OA-32: Implement "Grot Oiler" wargear for Big Mek
- [ ] Add once-per-battle wargear ability
- [ ] End of Movement phase: one model regains D3 wounds
- **Files**: UnitAbilityManager.gd, MovementPhase.gd
- **Validation**: Once per battle. D3 wounds healed at end of Movement phase.

### OA-33: Implement "Fix Dat Armour Up" for Big Mek in Mega Armour
- [ ] While leading, return 1 destroyed Bodyguard model in Command phase
- [ ] Model returns with full wounds
- **Files**: UnitAbilityManager.gd, CommandPhase.gd
- **Validation**: 1 destroyed Bodyguard model returned per Command phase while leading.

### OA-34: Implement "Mekaniak" for Mek/Big Mek On Warbike/Meka-dread
- [ ] End of Movement: heal D3 wounds on nearby Orks Vehicle
- [ ] Grant +1 to Hit for that vehicle until end of turn
- [ ] Once per vehicle per turn
- **Files**: UnitAbilityManager.gd, MovementPhase.gd, RulesEngine.gd
- **Validation**: D3 healed. +1 Hit for vehicle. Once per vehicle per turn.

### OA-35: Implement "Grot Riggers" for Trukk
- [ ] Start of Command phase: regain 1 wound
- **Files**: UnitAbilityManager.gd, CommandPhase.gd
- **Validation**: 1 wound regained at start of Command phase.

### OA-36: Implement "Piston-driven Brutality" for Deff Dread
- [ ] After charge move, select enemy in Engagement Range
- [ ] Roll D6: 2-5 = D3 mortal wounds, 6 = D3+3 mortal wounds
- **Files**: UnitAbilityManager.gd, ChargePhase.gd
- **Validation**: Triggers after charge. D6 roll determines MW (2-5: D3, 6: D3+3).

### OA-37: Implement "Shooty Power Trip" for Killa Kans
- [ ] When selected to shoot, roll D6
- [ ] 1-2 = D3 mortal wounds to self
- [ ] 3-4 = +1 Strength to ranged weapons
- [ ] 5-6 = +1 Attacks to ranged weapons
- **Files**: UnitAbilityManager.gd, ShootingPhase.gd
- **Validation**: D6 determines effect. Self-damage, +1S, or +1A applied correctly.

### OA-38: Implement "Splat!" for Big Gunz and Mek Gunz
- [ ] Big Gunz: re-roll Hit rolls of 1 when targeting units with 10+ models
- [ ] Mek Gunz: re-roll Hit rolls of 1 when at Starting Strength and targeting non-MONSTER/VEHICLE
- **Files**: UnitAbilityManager.gd, RulesEngine.gd
- **Validation**: Conditional re-roll 1s based on unit-specific criteria.

### OA-39: Implement "'Ard Case" wargear for Battlewagon
- [ ] Grant +2 Toughness to Battlewagon
- [ ] Disable Firing Deck ability
- **Files**: UnitAbilityManager.gd, army JSON validation
- **Validation**: +2T applied. Firing Deck disabled.

### OA-40: Implement "Blastajet Attack Run" for Wazbom Blastajet
- [ ] Re-roll Hit rolls of 1 when targeting non-FLY units
- **Files**: UnitAbilityManager.gd, RulesEngine.gd
- **Validation**: Re-roll 1s vs non-FLY targets. No re-roll vs FLY.

### OA-41: Implement "Big an' Shooty" / "Big an' Stompy" for Morkanaut/Gorkanaut
- [ ] Morkanaut: +1 to Hit for ranged attacks while Waaagh! active
- [ ] Gorkanaut: +1 to Hit for melee attacks while Waaagh! active
- **Files**: UnitAbilityManager.gd
- **Validation**: +1 Hit ranged (Morkanaut) or melee (Gorkanaut) during Waaagh!.

### OA-42: Implement "Scatter!" for Grot Tanks
- [ ] Reactive 6" move when enemy ends move within 9"
- [ ] Once per turn, not while in engagement range
- **Files**: UnitAbilityManager.gd, MovementPhase.gd
- **Validation**: 6" reactive move. Once per turn. Not in engagement range.

### OA-43: Implement "Waaagh! Effigy" aura for Stompa
- [ ] Friendly ORKS units within 12" get +1 to Battle-shock tests
- **Files**: UnitAbilityManager.gd, MoralePhase.gd
- **Validation**: +1 Battle-shock tests for friendly ORKS within 12".

### OA-44: Implement "Ded Glowy Ammo" aura for Kaptin Badrukk
- [ ] Enemy Infantry within 6" suffer -1 Toughness
- **Files**: UnitAbilityManager.gd, RulesEngine.gd
- **Validation**: -1T on enemy Infantry within 6".

### OA-45: Implement "Ghazghkull's Waaagh! Banner" aura for Ghazghkull
- [ ] Friendly ORKS within 12" of Makari during Waaagh! get Lethal Hits on melee weapons
- **Files**: UnitAbilityManager.gd, RulesEngine.gd
- **Validation**: Lethal Hits on melee for friendly ORKS within 12" of Makari during Waaagh!.

### OA-46: Implement "Plant the Waaagh! Banner" / "Da Boss Iz Watchin'" for Nob with Waaagh! Banner
- [ ] Once per battle: unit gains Waaagh! effects for one battle round
- [ ] During that Waaagh!: 4+ invuln save and OC 5
- **Files**: UnitAbilityManager.gd, FactionAbilityManager.gd
- **Validation**: Once per battle. Waaagh! effects for one round. 4+ invuln and OC 5.

### OA-47: Implement "Thievin' Scavengers" for Gretchin
- [ ] Start of Movement phase: D6 per controlled objective with Gretchin on it
- [ ] On 4+ on any die, gain +1 CP
- **Files**: UnitAbilityManager.gd, MovementPhase.gd
- **Validation**: D6 per objective with Gretchin. 4+ = +1CP.

### OA-48: Implement "Runtherd" for Gretchin
- [ ] Runtherd models use Toughness 2 while Gretchin models are alive in the unit
- **Files**: RulesEngine.gd
- **Validation**: Runtherd T2 while Gretchin alive. Reverts if all Gretchin killed.

### OA-49: Implement Beast Snagga sub-faction abilities
- [ ] Add abilities for all Beast Snagga units: Beastboss, Squighog Boyz, Kill Rig, Hunta Rig, Beast Snagga Boyz, Painboss, Wurrboy, Zodgrod, Mozrog
- [ ] Each unit has unique ability — define all in UnitAbilityManager
- **Files**: UnitAbilityManager.gd
- **Validation**: All Beast Snagga abilities defined and functional.

### OA-50: Implement remaining Ork vehicle abilities
- [ ] Implement Da Bigger Dey Are, Spiked Ram, Big Booms, Wall of Dakka, and other vehicle-specific abilities
- [ ] Define each in UnitAbilityManager with correct trigger and effect
- **Files**: UnitAbilityManager.gd
- **Validation**: All vehicle abilities functional.

---

## Phase 5: Display/Cosmetic

### OA-51: Display Freebooter Krew detachment ability and loot objective in UI
- [ ] UnitStatsPanel shows "Here Be Loot" detachment ability
- [ ] Loot objective visually distinguished on the board (highlight, icon, or label)
- **Files**: UnitStatsPanel.gd, Main.gd
- **Validation**: Detachment ability visible in stats panel. Loot objective clearly marked.

### OA-52: Display all unit abilities in UnitStatsPanel for Orks units
- [ ] All abilities from unit meta.abilities displayed with descriptions
- [ ] Conditional abilities show active/inactive state (e.g., Waaagh!-dependent abilities greyed out when inactive)
- **Files**: UnitStatsPanel.gd
- **Validation**: All abilities shown. Conditional state visible.

---

## Implementation Order

```
Phase 1: OA-1 → OA-2 → OA-3 → OA-4 → OA-5 → OA-6 → OA-7 → OA-8 (detachment + stratagems)
Phase 2: OA-9 → OA-10 → OA-11 → OA-12 → OA-13 → OA-14 → OA-15 → OA-16 → OA-17 → OA-18 → OA-19 → OA-20 (combat abilities)
Phase 3: OA-21 → OA-22 → OA-23 → OA-24 → OA-25 → OA-26 → OA-27 → OA-28 → OA-29 (movement abilities)
Phase 4: OA-30 → OA-31 → OA-32 → OA-33 → OA-34 → OA-35 → OA-36 → OA-37 → OA-38 → OA-39 → OA-40 → OA-41 → OA-42 → OA-43 → OA-44 → OA-45 → OA-46 → OA-47 → OA-48 → OA-49 → OA-50 (situational abilities)
Phase 5: OA-51 → OA-52 (display/cosmetic)
```

Dependencies:
- OA-1 (Here Be Loot) must be done first — OA-3, OA-4, OA-6, OA-7, OA-12, OA-14 reference loot objective
- OA-2 (enhancements) can be done in parallel with OA-1
- Phase 2 combat abilities are independent of each other
- Phase 3 movement abilities are independent of each other
- Phase 4 situational abilities are independent of each other
- Phase 5 depends on Phase 1 (OA-1 for loot objective display)

## Key Files Reference

| File | Primary Changes |
|------|----------------|
| FactionAbilityManager.gd | Freebooter Krew detachment registration, loot objective tracking, Waaagh! per-unit effects |
| UnitAbilityManager.gd | All unit ability definitions (combat, movement, situational, aura) |
| RulesEngine.gd | Hit/wound modifiers, re-rolls, AP improvements, FNP, invuln saves, critical hit overrides |
| StratagemManager.gd | All 6 Freebooter Krew stratagems |
| FactionStratagemLoader.gd | CSV loading for Freebooter Krew stratagems |
| CommandPhase.gd | Loot objective selection, Da Kaptin, Grot Riggers, Fix Dat Armour Up |
| MovementPhase.gd | Boardin' Rush, High-octane Fuel, Kunnin' Infiltrator, Deff from Above, Mekaniak, Thievin' Scavengers, Scatter! |
| ShootingPhase.gd | Ammo Runt prompt, Shooty Power Trip, Pulsa Rokkit |
| ChargePhase.gd | Full Throttle, Plummeting Descent, Piston-driven Brutality |
| FightPhase.gd | Drive-by Krumpin' consolidation override |
| MoralePhase.gd | Waaagh! Effigy aura |
| MovementController.gd | Redeployment UI for Kunnin' Infiltrator, reactive move for Krump and Run/Scatter! |
| UnitStatsPanel.gd | Display abilities and loot objective |
| Main.gd | Wire loot objective selection UI |
