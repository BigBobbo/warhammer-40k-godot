# Orks Freebooter Krew — Ability Audit Task List

Generated: 2026-03-09
Faction: Orks (ORK)
Detachment: Freebooter Krew (ID: 000001138)

---

## P0 — Core/Faction Abilities (affect every unit in the army)

### TASK: Implement "Here Be Loot" detachment ability for Orks Freebooter Krew

**Status:** Not implemented
**Priority:** P0 — This is the detachment ability that affects ALL units in a Freebooter Krew army.

**Rules (Wahapedia):**
At the start of the battle round, select one objective marker. Until the start of the next battle round, that objective marker is your loot objective.
Each time a model in an Orks Infantry, Orks Mounted or Orks Walker unit from your army makes an attack, that attack has the [SUSTAINED HITS 1] ability if either or both of the following are true:
- That model's unit is within range of your loot objective.
- That attack targets a unit within range of your loot objective.

**What's missing:**
- No "Freebooter Krew" entry in `FactionAbilityManager.DETACHMENT_ABILITIES` (only War Horde, Gladius Task Force, and Shield Host exist)
- No loot objective selection UI or tracking logic
- No Sustained Hits 1 conditional application based on proximity to loot objective
- No battle round start prompt to select loot objective

**Files to modify:**
- `40k/autoloads/FactionAbilityManager.gd` — Add Freebooter Krew detachment definition, loot objective tracking state, selection logic, and flag application to ORKS INFANTRY/MOUNTED/WALKER units near loot objective
- `40k/phases/CommandPhase.gd` — Add loot objective selection prompt at battle round start (before Command phase)
- `40k/autoloads/RulesEngine.gd` — Ensure Sustained Hits 1 from loot objective proximity is applied during hit resolution
- `40k/scripts/Main.gd` — Wire up loot objective selection UI signals
- `40k/dialogs/` — Create loot objective selection dialog (list of objective markers)

**Acceptance criteria:**
- [ ] Freebooter Krew detachment registered in FactionAbilityManager.DETACHMENT_ABILITIES
- [ ] At start of each battle round, player selects one objective marker as loot objective
- [ ] All Orks Infantry/Mounted/Walker units within range of loot objective get Sustained Hits 1
- [ ] All attacks targeting units within range of loot objective get Sustained Hits 1
- [ ] Loot objective resets each battle round
- [ ] Works identically for local and cloud-loaded armies
- [ ] UI shows which objective is the loot objective

---

### TASK: Register Freebooter Krew enhancements in army data

**Status:** Not implemented
**Priority:** P0

**Rules (Wahapedia):**
Freebooter Krew has 4 enhancements:
1. **Da Kaptin** (10pts, Warboss only): Once per battle round, at start of any phase, select one friendly ORKS unit that is Battle-shocked within 12" — it suffers D3 mortal wounds and is no longer Battle-shocked.
2. **Git-spotter Squig** (20pts, ORKS model only): Ranged weapons equipped by models in bearer's unit have [IGNORES COVER].
3. **Bionik Workshop** (15pts, Big Mek or Painboy only): At start of battle, roll D3 for random bionik — adds Move, Strength, or WS bonus to bearer's unit.
4. **Razgit's Magik Map** (25pts, ORKS model only): After deployment, redeploy up to 3 Orks Infantry units (can go to Strategic Reserves).

**What's missing:**
- No enhancement definitions for Freebooter Krew in any data files or manager code
- No enhancement resolution logic in any phase files
- Enhancement system appears to exist in Wahapedia CSVs but no code handles enhancement effects

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add enhancement ability definitions (Git-spotter Squig → Ignores Cover, Da Kaptin → remove Battle-shock, Bionik Workshop → random stat buff)
- `40k/autoloads/FactionAbilityManager.gd` — Add enhancement activation logic
- `40k/phases/CommandPhase.gd` — Da Kaptin trigger at start of any phase
- `40k/phases/DeploymentPhase.gd` or `40k/phases/FormationsPhase.gd` — Razgit's Magik Map redeployment

**Acceptance criteria:**
- [ ] All 4 enhancements defined and resolvable
- [ ] Enhancement effects apply correctly when equipped on valid models
- [ ] Once-per-battle-round tracking for Da Kaptin
- [ ] Random roll for Bionik Workshop at battle start
- [ ] Razgit's Magik Map allows redeployment after both armies deploy

---

## P0 — Freebooter Krew Stratagems

### TASK: Implement "Bash and Grab" stratagem for Freebooter Krew

**Status:** Not implemented (parsed from CSV but no Freebooter Krew stratagems loaded since detachment not registered)
**Priority:** P0

**Rules:** Fight phase, either player's turn, 1 CP. Target: One ORKS unit that hasn't fought. Effect: Until end of phase, re-roll Wound rolls for attacks targeting enemy units within range of loot objective.

**What's missing:**
- Freebooter Krew stratagems are in Stratagems.csv but won't load because the detachment isn't registered in FactionAbilityManager
- Effect requires loot objective proximity check (depends on Here Be Loot implementation)
- Re-roll Wound roll effect needs conditional scoping to "targets within range of loot objective"

**Files to modify:**
- `40k/autoloads/FactionAbilityManager.gd` — Register Freebooter Krew detachment so stratagems load
- `40k/autoloads/StratagemManager.gd` — May need custom effect handler for loot-objective-conditional re-rolls
- `40k/autoloads/FactionStratagemLoader.gd` — Verify parsing maps this correctly

**Acceptance criteria:**
- [ ] Stratagem appears in available stratagems during Fight phase
- [ ] Re-roll Wound rolls only apply against targets within range of loot objective
- [ ] 1 CP cost deducted correctly
- [ ] Once-per-phase restriction enforced

---

### TASK: Implement "Grab and Bash" stratagem for Freebooter Krew

**Status:** Not implemented
**Priority:** P0

**Rules:** Your Command phase, 1 CP. Target: One Orks unit (excluding Gretchin) within range of loot objective. Effect: Until start of next Command phase, Waaagh! is active for your unit, even if already called.

**What's missing:**
- No code to apply Waaagh! effects to a single unit independently of the global Waaagh! activation
- Requires loot objective proximity check
- Needs to exclude Gretchin units from targeting

**Files to modify:**
- `40k/autoloads/StratagemManager.gd` — Custom effect handler to apply per-unit Waaagh! effects
- `40k/autoloads/FactionAbilityManager.gd` — Function to apply Waaagh! flags to a single unit

**Acceptance criteria:**
- [ ] Stratagem available during your Command phase
- [ ] Only targets non-Gretchin ORKS units within range of loot objective
- [ ] Waaagh! effects (5+ invuln, +1S/A melee, advance+charge) apply to targeted unit only
- [ ] Effects last until start of next Command phase
- [ ] Works even if Waaagh! has already been called this battle

---

### TASK: Implement "Boardin' Rush" stratagem for Freebooter Krew

**Status:** Not implemented
**Priority:** P1

**Rules:** Your Movement phase, 1 CP. Target: One ORKS unit that hasn't moved. Effect: When unit Advances, don't roll — add 6" to Move instead.

**What's missing:**
- No custom Advance resolution that replaces the roll with flat +6"
- Movement phase needs to check for this stratagem effect when Advancing

**Files to modify:**
- `40k/autoloads/StratagemManager.gd` — Register effect
- `40k/phases/MovementPhase.gd` — Check for Boardin' Rush flag when resolving Advance moves
- `40k/scripts/MovementController.gd` — UI for selecting Advance with guaranteed 6"

**Acceptance criteria:**
- [ ] Stratagem available during your Movement phase before unit moves
- [ ] Advance roll skipped, +6" added to Move characteristic
- [ ] Only affects the targeted unit for the current phase

---

### TASK: Implement "Rolling Loot-heap" stratagem for Freebooter Krew

**Status:** Not implemented
**Priority:** P1

**Rules:** Your Shooting phase, 1 CP. Target: One Flash Gitz unit that hasn't shot. Effect: Until end of phase, ranged weapons have [ANTI-VEHICLE 4+].

**What's missing:**
- No Flash Gitz unit-specific targeting validation
- Anti-Vehicle 4+ keyword needs to be grantable via stratagem flag

**Files to modify:**
- `40k/autoloads/StratagemManager.gd` — Register effect with Flash Gitz unit restriction
- `40k/autoloads/RulesEngine.gd` — Apply Anti-Vehicle 4+ during wound resolution when flag active

**Acceptance criteria:**
- [ ] Only targets Flash Gitz units
- [ ] Grants Anti-Vehicle 4+ to all ranged weapons for the phase
- [ ] Anti-Vehicle 4+ triggers critical wounds on 4+ against VEHICLE keyword units

---

### TASK: Implement "Deck Fraggers" stratagem for Freebooter Krew

**Status:** Not implemented
**Priority:** P1

**Rules:** Your Shooting phase, 1 CP. Target: One ORKS unit that hasn't shot. Effect: Until end of phase, ranged weapons targeting INFANTRY units have [BLAST].

**What's missing:**
- Conditional BLAST grant (only when targeting INFANTRY)
- Need to add BLAST dynamically based on target keyword during attack resolution

**Files to modify:**
- `40k/autoloads/StratagemManager.gd` — Register effect
- `40k/autoloads/RulesEngine.gd` — Check for Deck Fraggers flag and apply BLAST when target is INFANTRY

**Acceptance criteria:**
- [ ] Stratagem available during your Shooting phase
- [ ] BLAST keyword added to ranged weapons only when targeting INFANTRY units
- [ ] BLAST bonus attacks calculated correctly (min 3 if 6+ models in target)

---

### TASK: Implement "Krump and Run" stratagem for Freebooter Krew

**Status:** Not implemented
**Priority:** P2

**Rules:** Opponent's Movement phase, 1 CP. Trigger: Just after an enemy unit falls back. Target: One ORKS unit that was within engagement range of that enemy at start of phase and is not within range of other enemies. Effect: Your unit can make a Normal move of up to 6".

**What's missing:**
- Reactive stratagem triggered during opponent's Movement phase
- Fall back detection for enemy units
- Post-fall-back 6" Normal move for freed Ork unit

**Files to modify:**
- `40k/autoloads/StratagemManager.gd` — Register with appropriate trigger
- `40k/phases/MovementPhase.gd` — Trigger check after enemy fall back
- `40k/scripts/MovementController.gd` — Allow 6" reactive move UI

**Acceptance criteria:**
- [ ] Triggers after enemy falls back from engagement with the targeted ORKS unit
- [ ] ORKS unit must not be engaged with other enemies
- [ ] Allows up to 6" Normal move
- [ ] Opponent's turn timing enforced

---

## P1 — Combat Abilities (directly affect hit/wound/save resolution)

### TASK: Implement "Gun-crazy Show-offs" ability for Flash Gitz

**Status:** Not implemented in UnitAbilityManager
**Priority:** P1

**Rules:** Each time a model in this unit targets the closest eligible target with its snazzgun, until the end of the phase, that weapon has an Attacks characteristic of 4.

**What's missing:**
- No entry in UnitAbilityManager.ABILITY_EFFECTS for "Gun-crazy Show-offs"
- Requires closest-target validation logic in ShootingPhase
- Weapon Attacks characteristic override based on targeting condition

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/autoloads/RulesEngine.gd` — Override Attacks to 4 when targeting closest eligible enemy
- `40k/phases/ShootingPhase.gd` — Validate closest target condition

**Acceptance criteria:**
- [ ] Snazzgun Attacks = 4 when targeting closest eligible enemy
- [ ] Snazzgun Attacks = 3 (base) when targeting non-closest enemies
- [ ] Closest target determined correctly using model-to-model distance

---

### TASK: Implement "Ammo Runt" wargear ability for Nobz and Flash Gitz

**Status:** Not implemented in UnitAbilityManager
**Priority:** P1

**Rules:** Once per battle (per ammo runt), when unit is selected to shoot, ranged weapons have [LETHAL HITS] until end of phase.

**What's missing:**
- No "Ammo Runt" entry in UnitAbilityManager.ABILITY_EFFECTS
- Need per-ammo-runt usage tracking (Nobz can have multiple)
- UI prompt when unit is selected to shoot: "Use Ammo Runt?"
- Lethal Hits grant to all ranged weapons

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition with once-per-battle tracking
- `40k/phases/ShootingPhase.gd` — Prompt for Ammo Runt activation
- `40k/autoloads/RulesEngine.gd` — Apply Lethal Hits flag when active

**Acceptance criteria:**
- [ ] Once-per-battle activation tracked per ammo runt
- [ ] Grants Lethal Hits to all ranged weapons for the phase
- [ ] UI prompt when unit is selected to shoot
- [ ] Multiple ammo runts tracked independently (Nobz can have 2)

---

### TASK: Implement "Tank Hunters" ability for Tankbustas

**Status:** Not implemented in UnitAbilityManager
**Priority:** P1

**Rules:** Each time a model in this unit makes a ranged attack that targets a MONSTER or VEHICLE unit, add 1 to the Hit roll and add 1 to the Wound roll.

**What's missing:**
- No "Tank Hunters" entry in UnitAbilityManager.ABILITY_EFFECTS
- Conditional +1 hit/+1 wound based on target keywords (MONSTER/VEHICLE)

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition with target-keyword condition
- `40k/autoloads/RulesEngine.gd` — Apply +1 hit and +1 wound when attacking MONSTER/VEHICLE targets

**Acceptance criteria:**
- [ ] +1 Hit and +1 Wound when attacking MONSTER or VEHICLE targets
- [ ] No bonus when attacking other unit types
- [ ] Applies to all ranged attacks by the unit

---

### TASK: Implement "Dat's Our Loot!" ability for Lootas

**Status:** Not implemented in UnitAbilityManager
**Priority:** P1

**Rules:** Each time a model in this unit makes a ranged attack, re-roll a Hit roll of 1. If that attack targets a unit within range of an objective marker, you can re-roll the Hit roll instead.

**What's missing:**
- No "Dat's Our Loot!" entry in UnitAbilityManager.ABILITY_EFFECTS
- Conditional re-roll scope: ones normally, full re-roll when target is on objective

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/autoloads/RulesEngine.gd` — Apply conditional re-roll (ones vs all based on target objective proximity)

**Acceptance criteria:**
- [ ] Re-roll Hit rolls of 1 on all ranged attacks
- [ ] Full Hit re-roll when target is within range of an objective marker
- [ ] Objective proximity check uses correct range calculation

---

### TASK: Implement "Drive-by Dakka" ability for Warbikers and Wartrakks

**Status:** Not implemented in UnitAbilityManager
**Priority:** P1

**Rules:** Each time a model in this unit makes a ranged attack that targets a unit within 9", improve the Armour Penetration characteristic of that attack by 1.

**What's missing:**
- No "Drive-by Dakka" entry in UnitAbilityManager.ABILITY_EFFECTS
- Range-conditional AP improvement

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/autoloads/RulesEngine.gd` — Apply AP improvement when target is within 9"

**Acceptance criteria:**
- [ ] AP improved by 1 for ranged attacks against targets within 9"
- [ ] No AP improvement for targets beyond 9"
- [ ] Applies to both Warbikers and Wartrakks

---

### TASK: Implement "Pyromaniaks" ability for Burna Boyz and Skorchas

**Status:** Not implemented in UnitAbilityManager
**Priority:** P1

**Rules:** Each time a model makes a ranged attack with a burna/Torrent weapon targeting an enemy within 6", re-roll Wound roll of 1. If target is also within range of an objective marker, re-roll the Wound roll instead.

**What's missing:**
- No "Pyromaniaks" entry in UnitAbilityManager.ABILITY_EFFECTS
- Conditional re-roll scope based on range (6") and objective proximity

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/autoloads/RulesEngine.gd` — Apply conditional wound re-rolls

**Acceptance criteria:**
- [ ] Re-roll Wound rolls of 1 with burna/Torrent weapons vs enemies within 6"
- [ ] Full Wound re-roll when target is also on an objective

---

### TASK: Implement "Da Boss' Ladz" ability for Nobz

**Status:** Not implemented in UnitAbilityManager
**Priority:** P1

**Rules:** While a Warboss model is leading this unit, each time an attack targets this unit, if the Strength of the attack is greater than the unit's Toughness, subtract 1 from the Wound roll.

**What's missing:**
- No "Da Boss' Ladz" entry in UnitAbilityManager.ABILITY_EFFECTS
- Defensive ability conditional on leader type (Warboss) and attack strength vs toughness comparison

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/autoloads/RulesEngine.gd` — Apply -1 Wound roll when S > T and Warboss leads

**Acceptance criteria:**
- [ ] -1 to Wound roll on incoming attacks when S > T
- [ ] Only applies when a Warboss model is leading the Nobz unit
- [ ] No effect when S <= T or no Warboss attached

---

### TASK: Implement "Dakkastorm" ability for Dakkajet

**Status:** Not implemented in UnitAbilityManager
**Priority:** P1

**Rules:** Each time this model makes a ranged attack, every successful Hit roll scores a Critical Hit.

**What's missing:**
- No "Dakkastorm" entry in UnitAbilityManager.ABILITY_EFFECTS
- Auto-Critical Hit on successful hit rolls needs a custom flag/handler

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/autoloads/RulesEngine.gd` — Override Critical Hit threshold to match successful hits

**Acceptance criteria:**
- [ ] All successful Hit rolls are treated as Critical Hits
- [ ] Sustained Hits and Lethal Hits trigger on every successful hit
- [ ] Only applies to ranged attacks

---

### TASK: Implement "Krumpin' Time" ability for Meganobz

**Status:** Not implemented in UnitAbilityManager
**Priority:** P1

**Rules:** While the Waaagh! is active for your army, models in this unit have the Feel No Pain 5+ ability.

**What's missing:**
- No "Krumpin' Time" entry in UnitAbilityManager.ABILITY_EFFECTS
- Conditional FNP 5+ that only applies when Waaagh! is active

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition with waaagh_active condition
- `40k/autoloads/RulesEngine.gd` — Apply FNP 5+ flag when Waaagh! is active

**Acceptance criteria:**
- [ ] FNP 5+ applies when Waaagh! is active
- [ ] FNP 5+ removed when Waaagh! deactivates
- [ ] Does not stack with other FNP sources

---

### TASK: Implement "Kustom Force Field" wargear ability for Big Mek

**Status:** Not implemented in UnitAbilityManager
**Priority:** P1

**Rules:** While the bearer is leading a unit, models in that unit have a 4+ invulnerable save against ranged attacks.

**What's missing:**
- No "Kustom Force Field" entry in UnitAbilityManager.ABILITY_EFFECTS
- Leader-conditional invulnerable save that only applies to ranged attacks

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition (condition: while_leading, effect: grant_invuln 4+ ranged only)
- `40k/autoloads/RulesEngine.gd` — Apply 4+ invuln save only during shooting/overwatch, not melee

**Acceptance criteria:**
- [ ] 4+ invulnerable save applies to led unit against ranged attacks
- [ ] Does not apply in melee
- [ ] Only active when Big Mek is leading the unit (alive and attached)

---

### TASK: Implement "Hold Still and Say 'Aargh!'" ability for Painboy

**Status:** Not implemented in UnitAbilityManager
**Priority:** P1

**Rules:** Each time an attack made by this model with its 'urty syringe scores a Critical Wound against a unit (excluding VEHICLE units), that unit suffers D6 mortal wounds.

**What's missing:**
- No entry in UnitAbilityManager.ABILITY_EFFECTS
- Weapon-specific critical wound effect (mortal wounds on crit wound with specific weapon)
- VEHICLE exclusion check

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/autoloads/RulesEngine.gd` — Apply D6 mortal wounds on critical wound with 'urty syringe, excluding VEHICLE targets

**Acceptance criteria:**
- [ ] D6 mortal wounds on Critical Wound with 'urty syringe
- [ ] No mortal wounds against VEHICLE targets
- [ ] Only applies to this specific weapon, not all Painboy attacks

---

### TASK: Implement "Prophet of Da Great Waaagh!" Crit Hit on 5+ for Ghazghkull

**Status:** Partially implemented — +1 Hit and +1 Wound are implemented, but Crit Hit on 5+ during Waaagh! is not
**Priority:** P1

**Rules:** While leading, +1 Hit and +1 Wound for melee attacks. PLUS: if Waaagh! active, Critical Hit on unmodified 5+.

**What's missing:**
- UnitAbilityManager has +1 Hit and +1 Wound but NOT the Crit Hit on 5+ during Waaagh! component
- Need conditional Crit threshold change during Waaagh!

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Extend "Prophet of Da Great Waaagh!" definition
- `40k/autoloads/RulesEngine.gd` — Apply Crit Hit on 5+ when Waaagh! active for this unit

**Acceptance criteria:**
- [ ] +1 Hit and +1 Wound always active while leading
- [ ] Crit Hit threshold lowered to 5+ during Waaagh!
- [ ] Both effects apply simultaneously during Waaagh!

---

## P2 — Movement/Positioning Abilities

### TASK: Implement "Full Throttle" ability for Stormboyz

**Status:** Not implemented in UnitAbilityManager
**Priority:** P2

**Rules:** This unit is eligible to declare a charge in a turn in which it Advanced or Fell Back.

**What's missing:**
- No "Full Throttle" entry in UnitAbilityManager.ABILITY_EFFECTS
- Charge eligibility after Advance/Fall Back

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/phases/ChargePhase.gd` — Check for Full Throttle flag

**Acceptance criteria:**
- [ ] Unit can charge after Advancing
- [ ] Unit can charge after Falling Back
- [ ] Applies permanently (always on)

---

### TASK: Implement "High-octane Fuel" ability for Warboss On Warbike

**Status:** Not implemented in UnitAbilityManager
**Priority:** P2

**Rules:** Each time this model's unit Advances, don't make an Advance roll. Instead, add 6" to Move.

**What's missing:**
- No "High-octane Fuel" entry in UnitAbilityManager.ABILITY_EFFECTS
- Auto-Advance (replace d6 roll with flat 6") while leading a unit

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/phases/MovementPhase.gd` — Override Advance roll with +6" when flag set

**Acceptance criteria:**
- [ ] No Advance roll made; Move increased by 6" when Advancing
- [ ] Only applies to units led by Warboss On Warbike

---

### TASK: Implement "Plummeting Descent" ability for Boss Zagstruk

**Status:** Not implemented in UnitAbilityManager
**Priority:** P2

**Rules:** You can re-roll Charge rolls made for this model's unit in a turn in which it was set up from Reserves.

**What's missing:**
- No "Plummeting Descent" entry in UnitAbilityManager.ABILITY_EFFECTS
- Conditional charge re-roll when arriving from Reserves

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/phases/ChargePhase.gd` — Apply charge re-roll flag when unit arrived from Reserves this turn

**Acceptance criteria:**
- [ ] Charge rolls can be re-rolled when unit set up from Reserves this turn
- [ ] No re-roll benefit on subsequent turns

---

### TASK: Implement "Kunnin' Infiltrator" ability for Boss Snikrot

**Status:** Not implemented in UnitAbilityManager
**Priority:** P2

**Rules:** Once per battle, in your Movement phase, instead of making a Normal move, remove unit from battlefield and set up 9"+ from all enemies.

**What's missing:**
- No "Kunnin' Infiltrator" entry in UnitAbilityManager.ABILITY_EFFECTS
- Teleport/redeployment mechanic in Movement phase
- Once-per-battle tracking

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/phases/MovementPhase.gd` — Add redeployment option when Snikrot's unit is selected to move
- `40k/scripts/MovementController.gd` — UI for redeployment placement

**Acceptance criteria:**
- [ ] Once per battle, can teleport instead of Normal move
- [ ] Must be set up 9"+ from all enemy models
- [ ] Usage tracked per battle

---

### TASK: Implement "Deff from Above" ability for Deffkoptas

**Status:** Not implemented in UnitAbilityManager
**Priority:** P2

**Rules:** Each time this unit ends a Normal move, select one enemy unit it moved over: roll one D6 per model in this unit, for each 4+, enemy suffers 1 mortal wound.

**What's missing:**
- No "Deff from Above" entry in UnitAbilityManager.ABILITY_EFFECTS
- Fly-over mortal wounds mechanic

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/phases/MovementPhase.gd` — Check for fly-over at end of Normal move

**Acceptance criteria:**
- [ ] After Normal move, can select one enemy unit moved over
- [ ] D6 per model in unit, 4+ = 1 mortal wound
- [ ] Only triggers on Normal moves

---

### TASK: Implement "Drive-by Krumpin'" ability for Nobz On Warbikes

**Status:** Not implemented in UnitAbilityManager
**Priority:** P2

**Rules:** Each time this unit Consolidates, each model can move up to 6" instead of 3".

**What's missing:**
- No "Drive-by Krumpin'" entry in UnitAbilityManager.ABILITY_EFFECTS
- Extended Consolidation move (6" vs 3")

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/phases/FightPhase.gd` — Override Consolidation distance to 6" when flag set

**Acceptance criteria:**
- [ ] Consolidation move is 6" instead of 3"

---

### TASK: Implement "Outflank" ability for Warbuggies

**Status:** Not implemented in UnitAbilityManager
**Priority:** P2

**Rules:** When arriving from Strategic Reserves, can set up in opponent's deployment zone.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/phases/MovementPhase.gd` — Override valid placement zones

**Acceptance criteria:**
- [ ] Can deploy in opponent's deployment zone from Strategic Reserves
- [ ] Other reserve restrictions still apply

---

### TASK: Implement "Clankin' Forward" ability for Morkanaut/Gorkanaut

**Status:** Not implemented in UnitAbilityManager
**Priority:** P2

**Rules:** Can move over enemy models (excluding MONSTER/VEHICLE) and terrain 4" or less.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/phases/MovementPhase.gd` — Override collision checks

**Acceptance criteria:**
- [ ] Can move over non-MONSTER/VEHICLE enemies and terrain ≤4"

---

### TASK: Implement "Stompin' Forward" ability for Stompa

**Status:** Not implemented in UnitAbilityManager
**Priority:** P2

**Rules:** Can move over all models (excluding TITANIC) and terrain 4" or less.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add ability definition
- `40k/phases/MovementPhase.gd` — Override collision for Stompa

**Acceptance criteria:**
- [ ] Can move over all non-TITANIC models and terrain ≤4"

---

## P3 — Situational/Conditional Abilities

### TASK: Implement "Bomb Squigs" (multi-squig) for Tankbustas

**Status:** Partially implemented — Kommandos version exists but Tankbustas has 2 bomb squigs
**Priority:** P3

**Rules:** Once per battle per squig (2 squigs), after Normal move, enemy within 12": on 3+, D3 mortal wounds.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Extend per-squig tracking

---

### TASK: Implement "Pulsa Rokkit" wargear for Tankbustas

**Status:** Not implemented
**Priority:** P3

**Rules:** Once per battle, when unit shoots: +1 S and +1 AP to all ranged weapons for the phase.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/phases/ShootingPhase.gd`

---

### TASK: Implement "Grot Oiler" wargear for Big Mek

**Status:** Not implemented
**Priority:** P3

**Rules:** Once per battle, end of Movement phase: one model regains D3 wounds.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/phases/MovementPhase.gd`

---

### TASK: Implement "Fix Dat Armour Up" for Big Mek in Mega Armour

**Status:** Not implemented
**Priority:** P3

**Rules:** While leading, return 1 destroyed Bodyguard model in Command phase.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/phases/CommandPhase.gd`

---

### TASK: Implement "Mekaniak" for Mek/Big Mek On Warbike/Meka-dread

**Status:** Not implemented
**Priority:** P3

**Rules:** End of Movement: heal D3 wounds + +1 Hit for nearby Orks Vehicle. Once per vehicle per turn.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/phases/MovementPhase.gd`, `40k/autoloads/RulesEngine.gd`

---

### TASK: Implement "Grot Riggers" for Trukk

**Status:** Not implemented
**Priority:** P3

**Rules:** Start of Command phase: regain 1 wound.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/phases/CommandPhase.gd`

---

### TASK: Implement "Piston-driven Brutality" for Deff Dread

**Status:** Not implemented
**Priority:** P3

**Rules:** After charge move: select enemy in Engagement Range, D6: 2-5=D3 MW, 6=D3+3 MW.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/phases/ChargePhase.gd`

---

### TASK: Implement "Shooty Power Trip" for Killa Kans

**Status:** Not implemented
**Priority:** P3

**Rules:** When selected to shoot, D6: 1-2=D3 MW self; 3-4=+1S ranged; 5-6=+1A ranged.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/phases/ShootingPhase.gd`

---

### TASK: Implement "Splat!" for Big Gunz and Mek Gunz

**Status:** Not implemented
**Priority:** P3

**Rules:** Re-roll Hit 1s conditionally (Big Gunz: 10+ model targets; Mek Gunz: at Starting Strength, non-MONSTER/VEHICLE).

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/autoloads/RulesEngine.gd`

---

### TASK: Implement "'Ard Case" wargear for Battlewagon

**Status:** Not implemented
**Priority:** P3

**Rules:** +2 Toughness, lose Firing Deck.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, army JSON validation

---

### TASK: Implement "Blastajet Attack Run" for Wazbom Blastajet

**Status:** Not implemented
**Priority:** P3

**Rules:** Re-roll Hit 1s vs non-FLY targets.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/autoloads/RulesEngine.gd`

---

### TASK: Implement "Big an' Shooty" / "Big an' Stompy" for Morkanaut/Gorkanaut

**Status:** Not implemented
**Priority:** P3

**Rules:** +1 Hit (ranged for Morkanaut, melee for Gorkanaut) while Waaagh! active.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`

---

### TASK: Implement "Scatter!" for Grot Tanks

**Status:** Not implemented
**Priority:** P3

**Rules:** Reactive 6" move when enemy ends move within 9" (once per turn, not in engagement).

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/phases/MovementPhase.gd`

---

### TASK: Implement "Waaagh! Effigy" aura for Stompa

**Status:** Not implemented
**Priority:** P3

**Rules:** Friendly ORKS within 12": +1 to Battle-shock tests.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/phases/MoralePhase.gd`

---

### TASK: Implement "Ded Glowy Ammo" aura for Kaptin Badrukk

**Status:** Not implemented
**Priority:** P3

**Rules:** Enemy Infantry within 6": -1 Toughness.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/autoloads/RulesEngine.gd`

---

### TASK: Implement "Ghazghkull's Waaagh! Banner" aura for Ghazghkull

**Status:** Not implemented
**Priority:** P3

**Rules:** Friendly ORKS within 12" of Makari during Waaagh!: melee weapons have Lethal Hits.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/autoloads/RulesEngine.gd`

---

### TASK: Implement "Plant the Waaagh! Banner" / "Da Boss Iz Watchin'" for Nob with Waaagh! Banner

**Status:** Not implemented
**Priority:** P3

**Rules:** Once per battle: unit gains Waaagh! for one battle round. During Waaagh!: 4+ invuln, OC 5.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/autoloads/FactionAbilityManager.gd`

---

### TASK: Implement "Thievin' Scavengers" for Gretchin

**Status:** Not implemented
**Priority:** P3

**Rules:** Start of Movement phase: D6 per controlled objective with Gretchin, 4+ on any = +1CP.

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`, `40k/phases/MovementPhase.gd`

---

### TASK: Implement "Runtherd" for Gretchin

**Status:** Implemented (OA-48)
**Priority:** P3

**Rules:** Runtherd models use T2 while Gretchin models alive in unit. Reverts to T4 when all Gretchin die.

**Files modified:**
- `40k/autoloads/RulesEngine.gd` — get_runtherd_toughness_override(), _unit_has_runtherd_ability()
- `40k/autoloads/UnitAbilityManager.gd` — "Runtherd" added to ABILITY_EFFECTS
- `40k/armies/Orks_2000.json`, `Orks_Upload_Mar7.json`, `Orks_2000_upload.json` — model_profiles + model_type

---

### TASK: Implement Beast Snagga sub-faction abilities

**Status:** Not implemented
**Priority:** P3

**Rules:** Multiple Beast Snagga units with unique abilities (Beastboss, Squighog Boyz, Kill Rig, Hunta Rig, Beast Snagga Boyz, Painboss, Wurrboy, Zodgrod, Mozrog).

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd` — Add all Beast Snagga ability definitions

---

### TASK: Implement remaining Ork vehicle abilities (Lifta Wagon, Big Trakk, Kannonwagon, Kill Tank, etc.)

**Status:** Not implemented
**Priority:** P3

**Rules:** Multiple vehicle-specific abilities (Da Bigger Dey Are, Spiked Ram, Big Booms, Wall of Dakka, etc.)

**Files to modify:**
- `40k/autoloads/UnitAbilityManager.gd`

---

## P4 — Display/Cosmetic

### TASK: Display Freebooter Krew detachment ability and loot objective in UI

**Status:** No UI
**Priority:** P4

**Files to modify:**
- `40k/scripts/UnitStatsPanel.gd`, `40k/scripts/Main.gd`

**Acceptance criteria:**
- [ ] UnitStatsPanel shows "Here Be Loot" detachment ability
- [ ] Loot objective visually distinguished on the board

---

### TASK: Display all unit abilities in UnitStatsPanel for Orks units

**Status:** Partially supported
**Priority:** P4

**Files to modify:**
- `40k/scripts/UnitStatsPanel.gd`

**Acceptance criteria:**
- [ ] All abilities from unit meta.abilities displayed with descriptions
- [ ] Conditional abilities show active/inactive state
