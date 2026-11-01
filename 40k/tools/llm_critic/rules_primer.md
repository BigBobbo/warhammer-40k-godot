# 11th edition rules the reviewer needs (verified against the core rules text)

Source: `docs/rules/40k_11th_edition_core_rules.txt` (11th edition core rules).
Rule numbers are the book's. These are the rules decisions most often hinge
on; for anything else, look it up in that file (Grep it) instead of guessing.

## Distances and engagement
- **Engagement range (02)**: within 2" horizontally and 5" vertically of a model.
  A unit with a model in engagement range of an enemy model is *engaged*.

## Movement (09)
- **Normal move (09.05)**: up to M. Must end unengaged.
- **Advance move (09.06)**: up to M + one D6 (the advance roll, average 3.5).
  Must end unengaged. **Until the end of the turn the unit cannot declare a
  charge** (or start an action).
- **Fall-back move (09.07)**: up to M, only when engaged. Until the end of the
  turn the unit cannot shoot, declare a charge or start an action.

## Shooting (10)
- **Normal shooting (10.04)**: unit must be unengaged and must NOT have advanced.
- **Assault shooting (10.05)**: a unit that advanced and has one or more
  [ASSAULT] weapons can shoot, but **only with its [ASSAULT] weapons**. A unit
  that advanced with no [ASSAULT] weapon cannot shoot at all.
- **Close-quarters shooting (10.06)**: engaged units shoot only [CLOSE-QUARTERS]
  weapons at units they are engaged with (MONSTER/VEHICLE: any weapon, -1 to hit
  unless [CLOSE-QUARTERS] at an engaged unit).
- **[RAPID FIRE X] (24.30)**: +X attack dice if the target was within **half the
  weapon's range** when targets were selected (24" weapon: within 12").
- **[HEAVY] (24.16)**: +1 to hit if the unit is unengaged, was not set up this
  turn and no model moved more than 3" this turn.
- **[BLAST] (24.05)**: +1 attack die per five models in the target unit.

## Terrain and visibility (13)
- **Benefit of cover (13.08)**: if every model in the target is INFANTRY/BEASTS/
  SWARM within a terrain area, or is not fully visible because of intervening
  terrain, the target has cover: **worsen the attack's BS by 1** (it is a to-hit
  penalty, not a save bonus).
- **Hidden (13.09)**: INFANTRY/BEASTS/SWARM in a terrain area with a dense
  feature, whose unit made no ranged attacks this turn or last turn, can only be
  seen by enemy models within 15" (detection range).
- **Obscuring (13.10)**: terrain areas with light or dense features are
  obscuring. If every line of sight between two models crosses an obscuring
  area that neither model is inside, they cannot see each other. A model INSIDE
  the ruin can see and be seen through that ruin.
- The decision bundle carries engine-computed line of sight from the acting
  unit to each enemy (`line_of_sight`); trust it over your own reading of the
  picture.

## Charge (11)
- **Eligible to declare (11.02)**: within 12" of an enemy unit, not engaged, and
  did NOT advance or fall back this turn.
- **Sequence (11.02)**: declare the charge with the UNIT (no targets yet) →
  roll 2D6 (the charge roll is the maximum move) → **then** select targets.
- **Charge move (11.04)**: before moving, select one or more enemy units that
  are within 12" AND **within the rolled distance** (measured base to base;
  engagement range does not add to it). After moving the unit must be engaged
  with **all** selected targets and with no other enemy unit. Charging units
  gain Fights First until end of turn.
- Consequence for judging the AI: the roll is made before targets are
  committed, so a "multi-target charge" is not an all-or-nothing gamble on the
  farthest target. With a high roll the unit can take several targets; with a
  low roll it can still take the nearest one. A double 1 (2) never succeeds.
  P(2D6 >= n): 2:100% 3:97% 4:92% 5:83% 6:72% 7:58% 8:42% 9:28% 10:17% 11:8% 12:3%.

## Fight (12)
- Consolidation (12.08), 3": if engaged, stay engaged; else if within 3" of an
  enemy unit, must move to engage it; else if within 3" of an objective, must
  move into range of it.

## Objectives (14)
- **Level of control (14.02)**: at the end of each phase and turn, sum the OC of
  each player's models in range; the higher total controls it, a tie means
  nobody does (unless secured, 14.03). Battle-shocked models have OC 0.
- **In range**: inside the terrain area of a terrain objective; for an objective
  marker, within 3" horizontally and 5" vertically.

## Primary mission scoring (this project's 11th edition mission cards)
- Each player has a Force Disposition (Take and Hold, Purge the Foe, Disruption,
  Priority Assets, Reconnaissance). The primary card is chosen by the pairing of
  the two dispositions; its exact awards are given in the decision bundle.
- **Caps (engine-enforced): at most 15 primary VP per turn and 45 primary VP
  per game.** Objectives therefore have sharply diminishing returns, and the
  shape depends on the card:
  - Per-objective cards (e.g. Battlefield Dominance: 3 VP per controlled
    objective, +2 per non-home objective while you hold your home) reach the
    cap at about three objectives: home + 2 non-home = 13 VP, a third non-home
    adds 2, a fourth adds 0.
  - Many cards pay a FLAT amount in the Command-phase check for controlling at
    least one non-home objective (e.g. Meatgrinder: 4 VP). A second non-home
    objective adds nothing to that award.
  The decision bundle includes a table of the acting player's Command-phase
  primary VP by objectives held, computed from their actual card with the cap
  applied. Use it: before praising a move that grabs an extra objective, read
  off the marginal VP it adds.
- Spreading thin is costly: a unit sent alone to an extra objective adds little
  or no primary VP, risks being picked off, and is missing where the army
  needs it. Taking an objective FROM the opponent can still be worth it, because
  it lowers their score even when yours is capped.
