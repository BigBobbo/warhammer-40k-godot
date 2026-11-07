# 11th edition core rules: errata, FAQs and rules commentary

Extracted 2026-11-07 from <https://wahapedia.ru/wh40k11ed/the-rules/core-rules/>, <https://wahapedia.ru/wh40k11ed/the-rules/rules-appendix/>. These are the official updates layered on top of the core rules. `40k_11th_edition_core_rules.txt` (launch PDF text) does **not** contain them; where they conflict, these win. Items are grouped under the nearest preceding numbered heading on the page, so a few FAQs sit one section early; errata titles carry their own section numbers. Refresh: download both pages, then run this file's generator, `extract_wahapedia_updates.py`.

| kind | count |
|---|---|
| Commentary | 115 |
| Errata | 8 |
| FAQ | 67 |
| Stratagem errata | 2 |


## 01.01.01 You

- **Commentary**: If a rule refers to ‘you’, it is referring to you the person, as the controlling player. _(rules-appendix)_

## 01.02 Units and Models

- **FAQ** Q: If a rule’s effect lasts until the end of a specific part of the battle (e.g. until the end of the phase, until the end of the turn), is that rule still in effect at the end of that part of the battle?
  A: Yes. For example, if an ability gave a unit +1 OC until the end of the turn, at the end of the turn, that unit would still have +1 OC. That unit would not have +1 OC at the start of the next turn. _(core-rules)_

## 01.02.01 Starting Strength and Half-Strength

- **Commentary**: The number of models a unit contains at the start of the first battle round is its starting strength . The starting strength of an attached unit is the number of models that unit contains at the start of the first battle round. Some rules refer to units being below starting strength , or at – or below – half-strength . The meaning of these terms varies depending on a unit’s starting strength , as shown below. UNIT STRENGTH STARTING STRENGTH OF 1 STARTING STRENGTH OF 2 OR MORE BELOW STARTING STRENGTH Model’s remaining wounds are less than its W characteristic. Number of remaining models in the unit is less than its starting strength. AT HALF-STRENGTH Model’s remaining wounds are half of its W characteristic. Number of remaining models in the unit is half of its starting strength. BELOW HALF-STRENGTH Model’s remaining wounds are less than half of its W characteristic. Number of remaining models in the unit is less than half of its starting strength. Example: A Captain (1 model) is attached to a unit of Intercessors (5 models). This attached unit has a starting strength of 6. If three Intercessors were destroyed, the unit would be at half-strength. If four Intercessors were destroyed, the unit would be below half-strength. If all of the Intercessors were destroyed, the remaining Captain would be below half-strength, despite having his full wounds remaining. SOME UNITS CANNOT BE AT HALF-STRENGTH If a model’s W characteristic or a unit’s starting strength cannot be evenly divided in half, that model or unit cannot be at half-strength (but can be below half-strength as described above). _(rules-appendix)_

## 01.02.02 Persisting Rules Effects

- **Commentary**: Some rules apply an effect that lasts until a certain duration has passed (e.g. until the start of your next turn). Such effects are known as persisting effects. If a persisting effect applies to a unit when you place it in strategic reserves or when it embarks within a TRANSPORT , make a note of that effect and its duration; if that unit is set up on the battlefield again, any persisting effects continue to apply to that unit for their full duration. If you have a rule that specifies when it is triggered (e.g. ‘In the Shooting phase ’) and it does not specify how long it is active for, it is only active for the duration of that specified period (e.g. until the end of that Shooting phase). After that period, that effect is no longer applicable/active. If a rule or effect is given to a unit and it does not specify how long it is active for, it is only active for the phase in which it was given. _(rules-appendix)_

## 01.02.03 Revived and Adding Models to a Unit

- **Commentary**: When a rule revives , resurrects, returns or adds models to a unit, the specified number of models are added to the unit. If a rule revives, resurrects or returns models to a unit, it does so through destroyed models from that unit. This cannot expand a unit beyond its starting strength. Unless otherwise stated, such models are added with all wargear and enhancements they started the battle with, and with their full W remaining. Models returned to a unit on the battlefield must be set up as follows: They must be set up in coherency with models in that unit that started that phase on the battlefield. They can be set up engaged with one or more enemy units, but only if those enemy units were already engaged with the unit that model is being returned to. If a leader or support model in an attached unit is destroyed and subsequently revived, they are still part of that attached unit and they must be returned to it if possible. When a model revives, resurrects, returns or is added to an embarked unit, if that TRANSPORT has sufficient remaining transport capacity for that model, that model is returned to that unit and is embarked. Otherwise, that model is destroyed, but it does not trigger rules that apply when a model is destroyed. _(rules-appendix)_

## 01.02.04 Not On The Battlefield

- **Commentary**: A unit that is embarked within a TRANSPORT or that is in strategic reserves is not on the battlefield. The following applies to such units: That unit is not visible to any other units (units are visible to themselves). Any other unit is not visible to that unit. Players cannot measure distances to or from that unit (units are within range of their own abilities). This means units not on the battlefield cannot be selected or targeted by any attack or rule that requires a unit to be visible or within a certain distance (other than their own abilities). Such units can still use their other rules, and are still units in the controlling player’s army and so can be affected by rules that require a player to select a unit from an army, as well as rules that affect all units in an army. The controlling player must make battle-shock rolls for units that are not on the battlefield in their Command phase if they are battle-shocked , or if they are at or below half-strength . _(rules-appendix)_

## 01.02.05 Other Model / Unit

- **Commentary**: When a rule refers to models or units ‘other’ than the one with that rule (or one already mentioned by that rule), it means a different model or unit to that original one. Different instances of the same datasheet are still considered to be ‘other’ units. _(rules-appendix)_

## 01.02.06 Splitting Units

- **Errata** 01.02.06 Splitting Units: Add: A unit must be split into two units, each containing as equal a number of models as possible (when splitting a unit in this way, make a note of which models form each of the two new units). If a rule states a specific starting strength of the split units, but this is not possible based on the number of models in the unit being split (e.g. due to attached Leader/Support models), split the unit as stated above. _(rules-appendix)_
- **Commentary**: Some rules allow you to split units into smaller units (e.g. the Transport ability of Drukhari Venoms ). When using such rules: The same models can only be subdivided in this way once (e.g. those smaller units cannot themselves be split further). If a rule is used to split a unit into multiple units before the battle, the starting strength of each individual unit is changed to be equal to the number of models in that unit. A unit must be split into two units, each containing as equal a number of models as possible (when splitting a unit in this way, make a note of which models form each of the two new units). If a rule states a specific starting strength of the split units, but this is not possible based on the number of models in the unit being split (e.g. due to attached Leader / Support models), split the unit as stated above. Errata Show 01.02.06 Splitting Units Add: A unit must be split into two units, each containing as equal a number of models as possible (when splitting a unit in this way, make a note of which models form each of the two new units). If a rule states a specific starting strength of the split units, but this is not possible based on the number of models in the unit being split (e.g. due to attached Leader/Support models), split the unit as stated above. _(rules-appendix)_

## 01.02.07 Describing Units

- **Commentary**: When a rule mentions a unit, it may have a descriptor for the unit (e.g. TERMINATOR unit, hidden unit, battle-shocked unit, visible unit, controlling unit). For such descriptors to apply to a unit, that unit must have at least one model in that unit that meets that descriptor. This does not give that rule to every model in the unit, unless that rule specifically states that it gives that rule to the unit, in which case every model in that unit gains that rule, as described in Units and Models ( 01.02 ). Example: A hidden unit would be a unit that has a model in it that is hidden. _(rules-appendix)_

## 01.02.08 A (Unit/Model/Object)

- **Commentary**: Some rules may refer to ‘a’ unit/model/object without specifying an exact number. In such cases, the meaning is’one or more’, rather than exactly one. Example: If a rule has a condition that requires a unit to be ‘within range of an objective’, that condition is still met if that unit is within range of more than one objective. _(rules-appendix)_

## 01.02.09 Tokens

- **Commentary**: Tokens are gaming aids that some rules instruct you to place next to model/unit to remind you and your opponent that a model/unit either has a limited-use ability or is under the effects of a particular rule. Tokens are not counted as models for any purposes (even if they are being represented by a model). If another model needs to move into the space occupied by a token, reposition the token to allow that move to be made. _(rules-appendix)_

## 01.02.10 Adding a new unit to your army

- **Commentary**: Some rules add a new unit to your army during a battle. That unit’s starting strength is determined when it is added to your army, but is otherwise determined in the same way as for other units. _(rules-appendix)_

## 01.02.11 All Types of Model

- **Commentary**: When a rule mentions ‘all types of model’, this is inclusive of friendly and enemy models and all keywords , e.g. MONSTER / VEHICLE models. _(rules-appendix)_

## 01.02.12 Replacing One Model with Another

- **Commentary**: When a rule tells you to place one model where another model was, or to replace one model with another: Mark the point on the battlefield beneath the centre of the base of the model to be replaced (or its central axis, for a unit with FRAME). Place the other model so that the centre of its base (or its central axis, for a unit with FRAME) is directly over that point. If you cannot do the above because you would need to place one model on top of another model, or because you would need to place a model overhanging the battlefield edge, instead place the new model as close as possible to that point. _(rules-appendix)_

## 01.03.01 Player’s Rules

- **Commentary**: During the game, players will sometimes need to know which rules are theirs, as opposed to their opponent’s. The following are considered a player’s rules: Any army rules they have. Any detachments in their army. Any stratagems they use. Any enhancements that units or models in their army have. Any abilities or rules found on their units’ datasheets. Rules that have restrictions (e.g. ‘Once per battle/turn/phase’) only apply to the player whose rule it is. Some missions may introduce additional rules that take effect in the battle. Where this is the case: If the rule is used by a player, it is treated as one of that player’s rules. If it is not used by a player, and always takes effect, such a rule is resolved before any of the active player’s rules, in an order of their choosing. _(rules-appendix)_

## 01.03.02 Rules Sequencing

- **Commentary**: At any point in the game, the players will have rules that they can or must use, which may occur at the same time another player can or must use a rule. Unless otherwise stated, these are activated in the following order: All of the active player’s rules that must be used, in an order of their choosing. All of the active player’s rules that they can optionally use and wish to use, in an order of their choosing. All of the opposing player’s rules that must be used, in an order of their choosing. All of the opposing player’s rules that they can optionally use and wish to use, in an order of their choosing. If another rule could be used after a rule has resolved during this sequence but before other rules in that same timing have resolved, those new rules do not trigger until all the remaining rules to be resolved in that same timing have been resolved. Example: The active player’s unit has an ability enabling it to make a normal move after it has shot. An enemy unit targeted by that unit has an ability enabling it to shoot back at a unit that shot at it. The active player’s rule is resolved first, followed by the opposing player’s rule. _(rules-appendix)_

## 01.04.01 Within / Wholly Within

- **Commentary**: Rules in Warhammer 40,000 will often apply to models or units that are within or wholly within a certain distance. The following definitions explain what these terms mean: Within: If a rule says it applies ‘within’ a specified distance, it applies at any distance that is not more than that distance. For example, within 1" means any distance that is not more than 1" away Model/Unit Within: A model is within a specified distance if any part of its base is within that distance. A unit is within a specified distance if one or more of its models are within that distance. Model/Unit Wholly Within: A model is wholly within a specified distance if every part of its base is within that distance. A unit is wholly within if every model in that unit is wholly within the specified distance. A model with the FRAME keyword is wholly within a specified distance if all parts of that model are within the specified distance. Example : A model is wholly within a terrain area if no part of its base extends beyond the footprint of that terrain area . A unit is wholly within a specified distance if every model in that unit is wholly within that distance. _(rules-appendix)_

## 01.04.02 Closest Or Nearest Model/Unit

- **Commentary**: When a rule refers to the closest or nearest model or unit, this is the closest model or unit to the model or unit using that rule. If two or more are equally close, the controlling player of the model or unit using that rule selects which is the closest for the purposes of that rule. _(rules-appendix)_

## 01.04.03 As Close As Possible

- **Commentary**: If a rule instructs you to move a model as close as possible to a unit or model you must end that model’s move in base contact with that unit or model if its move is sufficient to do so without breaking any other restrictions (such as coherency), or as close as you can achieve if its move is not sufficient. If a model is already as close as possible to a unit or model when it is instructed to make a move as close as possible towards a unit or model, that model cannot be moved, but still counts as having made the move in question. If a rule instructs you to move a model as close as possible to an objective you must end that model’s move within range of an objective if its move is sufficient to do so without breaking any other restrictions (such as coherency), or as close as you can achieve if its move is not sufficient. If that model is already within range of an objective it can move up to the maximum distance of that move but must end its move still within range of that objective. _(rules-appendix)_

## 01.04.04 Base Contact or Base to Base Contact

- **Commentary**: When two models’ bases are touching, they are in base contact – also known as base-to-base contact – and are as close as possible ( 01.04.03 ). When moving a model from your army into base contact with an enemy model during a move, if that enemy model overhangs its base such that it is not physically possible to be in base contact with that model, until the end of the turn, those models are considered to be in base contact with each other while all of the following are true: The distance your model could move was sufficient to move it into base contact with the enemy model if there was no overhang. The models are as close as possible together. Any part of one model is within 1" of any part of the other model. _(rules-appendix)_

## 01.04.05 Table Quarters

- **Commentary**: When a rule refers to a table quarter, or table quarters, divide the battlefield with imaginary lines 1mm thick drawn lengthwise and widthwise through the centre of the battlefield to create four equal rectangles. These rectangles are the table quarters. _(rules-appendix)_

## 01.04.06 Drawing a Line

- **Commentary**: When a rule tells you to draw a line, unless otherwise stated: That line has no thickness. That line must be straight. _(rules-appendix)_

## 01.05.01 Automatically Successful/Passes/Hits/Wounds

- **Commentary**: When a dice roll or test is automatically successful or automatically passes/hits/wounds, do not roll the dice and instead move to the next step of the sequence for that roll as if the required result had been rolled. Any rules that take effect on a particular dice result or roll result do not take effect. Example: If a hit roll is automatically successful, move straight to the Wound Rolls step for that attack. Such a hit roll is not a critical hit. Example: If a wound roll is automatically successful, move straight to the Save Rolls step for that attack. Such a wound roll is not a critical wound. _(rules-appendix)_

## 01.05.02 Re-rolls

- **Commentary**: Some rules allow you to re-roll a dice roll, which means you get to roll some or all of the dice again. When a rule lets you re-roll one or more dice, the following points apply: If a rule allows you to re-roll a dice roll that was made by adding several dice together (e.g. 2D6, 3D6, etc.) then you must re-roll all of those dice again. You can never re-roll a dice more than once, and re-rolls happen before modifiers (if any) are applied. A re-rolled dice is still considered to be a dice roll and, as such, any rules that can be triggered by a dice roll can also be triggered by a re-rolled dice. _(rules-appendix)_

## 01.05.03 Modifying Dice Rolls

- **Commentary**: See Modifiers ( 02.02.01 ). _(rules-appendix)_

## 01.05.04 Ignoring Roll Modifiers

- **Commentary**: See Ignore Modifiers ( 02.02.02 ) _(rules-appendix)_

## 01.05.05 Roll Off

- **Commentary**: Some rules instruct players to roll off. To do so, both players roll one D6, and whoever rolls highest wins the roll-off. If there is a tie for the highest roll, roll off again. _(rules-appendix)_

## 01.05.06 Doubles Or Triples

- **Commentary**: When making a dice roll, a double is a roll that includes any two dice of the same result, and a triple is a roll that includes any three dice of the same result. _(rules-appendix)_

## 01.05.07 Highest or Lowest Dice Result

- **Commentary**: If a rule refers to the highest dice result and a dice roll involves multiple dice, if more than one of those dice have the same value, and that value is the highest, the active player must select one of those dice to be the highest dice result. If a rule refers to the lowest dice result and a dice roll involves multiple dice, if more than one of those dice have the same value, and that value is the lowest, the active player must select one of those dice to be the lowest dice result. _(rules-appendix)_

## 01.05.08 Treated As, Set To (Dice Roll)

- **Commentary**: When a dice result is ‘treated as’ or ‘set’ to another value, any rules that would take effect if that value had been rolled take effect. This may result in a value that is greater than a value that could be rolled on a D6 dice. _(rules-appendix)_

## 01.06.01 Leadership Test

- **Commentary**: Some rules may use the term Leadership test, this is the same as leadership roll . _(core-rules)_

## 01.07 Battle-shock Rolls

- **FAQ** Q: If a unit has a rule that allows it to start an action when it is battle-shocked can it also continue doing that action if it becomes battle-shocked after starting an action?
  A: Yes _(core-rules)_

## 01.07.01 Battlefield Morale

- **Commentary**: The morale and organisation of troops can waver and break during battle. This is checked using battle-shock rolls , most commonly in the Command phase . Failing such a roll represents the unit’s courage faltering due to taking casualties or through other disruption, reducing its battlefield effectiveness. Similarly, some rules will require you to check a unit’s readiness by making a leadership roll . _(rules-appendix)_

## 01.07.02 Battle-shock Test

- **Commentary**: The term Battle-shock test is the same as battle-shock roll . _(rules-appendix)_

## 02.01.01 Datasheet Name and Keywords

- **Commentary**: As well as the keywords listed in each datasheet’s Keywords section, each datasheet name acts as an additional keyword for that unit. _(rules-appendix)_

## 02.02 2. Profiles

- **FAQ** Q: My unit has access to a rule that changes the Damage characteristic of an incoming attack to 0. When such an attack is allocated to a model in that unit, is the Damage changed before or after save rolls?
  A: After. _(core-rules)_
- **FAQ** Q: How do modifiers to the charge roll (or to the maximum distance of the charge move, such as Take to the Skies) affect the selection of charge targets?
  A: A charging unit may only select charge targets that are within the maximum distance of their charge roll, including any modifiers. If such a modifier occurs after selecting a charge target and causes that charge target to no longer be within the maximum distance, the charging unit would then select new targets (Target No Longer Eligible Or Viable, 04.03.03). Example: A unit’s charge roll is 7", and that unit has a datasheet ability which adds 1 to charge rolls: that charge’s maximum distance is 8", so you can select charge targets within 8". Example: A FLYING unit chooses to take to the skies and rolls a charge roll of 9"; that charge’s maximum distance is 7" (9" minus the 2" from taking to the skies), so you can select charge targets within 7". _(core-rules)_

## 02.02.01 Modifiers

- **Commentary**: What are Modifiers? Many rules in the game modify a value, characteristic or roll elsewhere in the game. A rule that does so is known as a modifier. A value that has been changed is a modified rule (e.g. modified characteristic, modified roll, modified value, etc). One of the most common ways for modifiers to be presented is as +1 or -1 to a characteristic, roll or value. If the rule has +1 to a characteristic, it improves it by the value after the ‘+’ symbol. Example: ‘This weapon has +1 AP ’ would improve an AP characteristic of -2 to -3. If the rule has -1 to a characteristic, it worsens it by the value after the ‘-’ symbol. Example: ‘This unit has -1 Sv ’ would worsen a Sv characteristic of 3+ to 4+. Applying Modifiers This section presents the various ways rules may be modified. All modifiers are cumulative. When a value is modified (e.g. characteristic, dice roll, distance), do so in the following order. If a rule instructs you to change or replace one value with a specified value, you must first change the relevant value to the new value. Note that rules that modify a characteristic in this step to a new value of ‘0’, ‘-’ or ‘*’ cannot be modified by other rules (in such cases, skip steps 2-5). Apply multiplication modifiers. Apply addition modifiers. Apply division modifiers. Apply subtraction modifiers. Round any fractions up after applying all modifiers. When Modifying Characteristics When modifying characteristics, unless otherwise stated, the following points also apply: Characteristics of ‘-’, ‘*’ and ‘N/A’ can never be modified. Rules that modify a model’s WS and/or BS characteristic modify the WS and/or BS characteristic of every weapon equipped by that model. After all modifiers have been applied: M cannot be less than 1"". T cannot be less than 1. Sv cannot be 1+ or better. InSv cannot be 1+ or better. Ld cannot be 4+ (or better) or 9+ (or worse). OC cannot be less than 0 or ‘-’. Range characteristics cannot be less than 1". A cannot be less than 1. WS cannot be 1+ (or better) or 7+ (or worse). BS cannot be 1+ (or better) or 7+ (or worse). S cannot be less than 1. AP cannot be worse than 0. D cannot be less than 1. When these terms are used in rules, the affected characteristics are being modified, and the following points apply: Improving WS, BS, Sv and Ld: When improving a WS , BS , Sv or Ld characteristic, subtract the appropriate amount from the number before the plus sign, e.g. improving a WS of 3+ by 1 would result in a WS of 2+. Worsening WS, BS, Sv and Ld: When worsening a WS , BS , Sv or Ld characteristic, add the appropriate amount to the number before the plus sign, e.g. worsening a WS of 3+ by 1 would result in a WS of 4+. Improving AP: When improving an Armour Penetration characteristic, subtract the appropriate amount from the characteristic, e.g. improving an AP of -1 by 1 would result in an AP of -2; improving an AP of 0 by 1 would result in an AP of -1. Reducing or Worsening AP: When reducing or worsening an Armour Penetration characteristic, add the appropriate amount to the characteristic, to a maximum of 0, e.g. reducing/worsening an AP of -1 by 1 would result in an AP of 0; reducing/worsening an AP of 0 by 1 would result in an AP of 0. Improving or Worsening Other Characteristics: When instructed to improve/worsen a characteristic that does not include a ‘+’ or ‘-’ symbol, add/subtract the specified amount to/from that characteristic (e.g. to improve a S by 1, add 1 to it). When Modifying Dice Rolls When modifying dice rolls, the following points also apply: Modifiers are applied after any re-rolls of that dice roll. Rules that refer to the value of an ‘unmodified’ dice roll are referring to the dice result after any re-rolls, but before modifiers. A dice result can be modified above its maximum possible value (for example, a D6 roll can be modified above 6). A result that would be less than 1 is changed to a result of 1. Hit rolls and wound rolls can never be modified by more than -1 or +1. After all the cumulative modifiers to such a roll have been calculated, if the total modifier would be: -2 or worse, it is changed to -1. +2 or better, it is changed to +1. Charge rolls cannot be greater than 12. After all the cumulative modifiers to a charge roll have been calculated, if the result would be 13 or more, it is changed to 12. Other Modified Rules The following rules apply to various rules and effects found throughout the game. Detection range and Lone Operative cannot be better than 9" or worse than 30". A stratagem cannot have its CP increased by more than 1 or reduced to below 0 after all modifiers have been applied. _(rules-appendix)_

## 02.02.02 Ignore Modifiers

- **Commentary**: Some rules enable a player, weapon, model or unit to ignore modifiers . When using such rules, the following points apply: Unless otherwise stated, that rule allows you to ignore modifiers to the unit’s rolls and the unit’s profile and weapon characteristics. When a rule states you can ignore modifiers to a stated roll or characteristic, you can choose to ignore all of those modifiers, or only some of them. For example, you can still choose to apply positive/beneficial modifiers while ignoring negative/detrimental modifiers. Example: Your unit can ignore characteristic modifiers and is under the effect of +2" M and -2" M. You can choose to ignore the -2" M, meaning that unit’s M characteristic will only be modified by the +2" M. Example: Your unit’s ranged attacks can ignore roll modifiers and are under the effect of +1 to hit rolls and -1 to hit rolls. You can choose to ignore the -1 to hit rolls, meaning those attacks will only be affected by the +1 to hit rolls. _(rules-appendix)_

## 02.02.03 Random Characteristics

- **Commentary**: Random Movement: When a unit with a random M characteristic is selected to move , determine the entire unit’s move distance by rolling the indicated number of dice. Random Attacks: If a weapon has a random A characteristic, that characteristic is determined when generating attacks for that weapon at the Resolve Attacks step ( 04.03 ). If several weapons with random A characteristics are making identical attacks , generate the attacks for each of those weapons individually, and group them all together. Random Damage: If a weapon has a random D characteristic, then each time an attack made with it inflicts damage, the controlling player determines that weapon’s characteristic when the opposing player has selected a model in the target unit to allocate that attack to. When determining a random D characteristic, the dice roll made is called a damage roll . Where a D characteristic includes an operator (e.g. a ‘+’, as in D6+1), the value after the operator is part of that D characteristic – it is not a modifier. Other Random Characteristics: For all other characteristics, roll to determine the value on an individual, per-model or per-weapon basis each time that characteristic is required. _(rules-appendix)_

## 02.02.04 Healing Or Regaining Lost Wounds

- **Commentary**: When a unit heals or regains a number of wounds, it regains up to that number of lost wounds. For each wound healed or regained, consult the following: If that unit has one or more models that does not have its full wounds remaining, select one of those models; that model regains one lost wound. If all models in that unit have their starting number of wounds, but one or more models from that unit are currently destroyed, revive one of those destroyed models (excluding CHARACTER models), with one wound remaining. This cannot cause a model to have more wounds remaining than it started the battle with. If a rule states that a model heals or regains a number of wounds, only that model can regain wounds up to its starting number of wounds. Any excess regained wounds are lost and do not cause a destroyed model from that unit to revive . _(rules-appendix)_

## 02.02.05 Full Wounds Remaining

- **Commentary**: A model has its full wounds remaining if it has the same number of wounds remaining as its W characteristic. _(rules-appendix)_

## 02.02.06 Characteristic Modifiers & Modified Characteristics

- **Commentary**: See Modifiers ( 02.02.01 ). _(rules-appendix)_

## 02.03.01 Rules With Multiple Conditions And Effects

- **Commentary**: Some rules have multiple conditions, with the second, more specific condition conferring an improved rule, either instead of the first condition’s rule or as well as it. Such rules require both the first condition and the second condition to be satisfied for the improved rule to apply. For example, an ability reads: ‘This unit’s ranged attacks that target the closest eligible target can: Re-roll hit rolls of 1. Or: If that target is within range of an objective your opponent controls, re-roll hit rolls.’ In order for those attacks to re-roll hit rolls , that target must be both the closest eligible target and within range of an objective your opponent controls. _(rules-appendix)_

## 02.04 4. Weapons

- **FAQ** Q: My rule says that "this units ranged attacks have +1 A ", do each of my attacks get an extra attack dice?
  A: No, it increases the A characteristics of the unit's ranged weapons by 1. _(core-rules)_

## 02.04.01 Weapons With No Strength

- **Commentary**: If a weapon has no S characteristic (because it is’-’, or for any other reason) and a rule interacts with that weapon’s S , that weapon has S 1 for that interaction. _(rules-appendix)_

## 02.05 5. Keywords

- **FAQ** Q: Do rules that affect a keyword include multi-word keywords that contain that keyword? For example, would rules that affect COMMISSAR units affect a unit that has the COMMISSAR GRAVES keyword?
  A: No. _(core-rules)_

## 02.05.01 Using Keywords & Mixed Keywords in Units

- **Commentary**: When using keywords , the following points apply: A unit has all the keywords of all models in that unit. A model only has its own keywords. If a rule specifies that it applies to a unit with a keyword, it applies to a unit which includes one or more models with that keyword. If a rule specifies that it applies to a model with a keyword, it only applies to a model with that keyword. If a rule specifies that it applies to ‘non- KEYWORD’ models/units, it only applies to models/units that do not have that keyword. For example, if a rule applies to non- VEHICLE units, it only applies to units that do not have the VEHICLE keyword. Some units can contain models that have different keywords. While this is the case, such a unit is considered to have all of the keywords of all of its models, and so is affected by any rule that applies to units with any of those keywords. Remember that attacks are made against units, not models. If a rule only applies to models with a specific keyword, then it instead only applies to models in such a unit that have the correct keyword. A rule with a comma-separated list of keywords, or a series of keywords separated by slashes (‘/’), or two keywords separated by the word ‘or’ (e.g. ‘an IMMORTALS, DEATHMARKS or LYCHGUARD unit’) refers to a model/unit that has any one of those keywords. A rule with multiple adjacent keywords (e.g. ‘an AELDARI GUARDIANS unit’) only refers to a model/unit that has all of those keywords. Some older rules use keywords without specifying model or unit: for example, MONSTER / VEHICLE or TRANSPORT. These rules refer to units with those keywords. Singular and plural instances of the same keyword function in the same way. _(rules-appendix)_

## 02.06 6. Unit Composition and Other Rules

- **FAQ** Q: The Munitorium Field Manual shows my unit can attach to different units then are on it's datasheet, which do I use?
  A: Use the Munitorium Field Manual. _(core-rules)_

## 02.06.01 Bearer

- **Commentary**: The bearer of a weapon, enhancement or item of wargear is the model equipped with it. _(rules-appendix)_

## 02.06.02 Unit's Equipment

- **Commentary**: When a rule refers to a unit’s equipment, it refers to all of the wargear equipped by models in that unit. _(rules-appendix)_

## 03.01.01 Different Move Characteristics

- **Commentary**: When making a move type whose maximum distance uses the unit’s M characteristic, if different models in the moving unit have different M characteristics, the maximum distance for that move will be different for those models. Example: If a unit makes a normal move and all models in that unit have an M characteristic of 6" except for one model with an M characteristic of 9", that model’s maximum distance for that move is 9", while the other models’ maximum distance is 6". While that unit is making that move, all other restrictions must be met. _(rules-appendix)_

## 03.01.02 Moving Over Or Through Models

- **Commentary**: Some models have a rule that enables them to ‘move over models’, ‘move through models’ or ‘move over models as if they were not there’ when making a move. When moving a model with such a rule, it can make its move through enemy models, but must follow all other restrictions of the move they are making. _(rules-appendix)_

## 03.01.03 Random Movement

- **Commentary**: See Random Characteristics ( 02.02.03 ) _(rules-appendix)_

## 03.01.04 When Moving Up To

- **Commentary**: Some rules allow a unit to make a stated < move type > of up to X". That stated distance is the maximum distance for that move. _(rules-appendix)_

## 03.02.01 If You Cannot Set Up a Unit

- **Commentary**: While having to set up a unit as the result of a move type , if you have to return a unit’s models to their previous positions because it is not possible to set them all up, that unit has not been selected to move . This means it can be selected to move later, so could either attempt another set up or remain stationary ( 09.04 ). _(rules-appendix)_

## 03.02.02 Setting Up Large Models

- **Commentary**: If a model cannot meet all of its set up restrictions because it is too large, consult the relevant section below: During Deployment: If a model is so large that its base cannot physically be set up wholly within your deployment zone, it must be set up so that it is touching your battlefield edge. During a turn in which such a large model is set up on the battlefield, that model’s unit cannot do any of the following: Make a normal / advance / fall-back / charge move. Make any attacks with ranged weapons. Some large models, typically AIRCRAFT , have wings and other parts that extend significantly beyond their base. Such models can overhang a deployment zone if it is not possible to set them up otherwise, but when setting them up, their base must still be wholly within that deployment zone. From Strategic Reserves: If a model is so large that its base cannot physically be set up wholly within the distance required of the battlefield edge, it must be set up so that it is touching a battlefield edge. During a turn in which such a large model is set up on the battlefield (excluding AIRCRAFT models), that model’s unit cannot do any of the following: normal/advance/fall-back/charge move. Make any attacks with ranged weapons. Some large models, typically AIRCRAFT , have wings and other parts that extend significantly beyond their base. Such models can overhang a battlefield edge if it is not possible to set them up otherwise, but when setting them up, they must still be more than 8" away from all enemy units. Disembarking from a Transport: When a unit disembarks from a TRANSPORT , it must be set up wholly within 3" of that model. If a disembarking model is so large that it is not possible to set it up wholly within 3" (typically because it is itself larger than 3" in all directions), set that model up with its base within 1" of that TRANSPORT ’s base (or hull), and not engaged with any enemy units. _(rules-appendix)_

## 03.02.03 Redeployments

- **Commentary**: When a player uses a rule that lets them redeploy their unit, they remove that unit from the battlefield, then deploy it again using all the normal rules (e.g. if all the models in the redeploying unit have the Infiltrators ability, that unit can be set up using that ability). _(rules-appendix)_

## 03.03 Coherency

- **FAQ** Q: Do models destroyed when a unit is out of coherency count for mission objectives?
  A: Yes. _(core-rules)_
- **FAQ** Q: When checking coherency for my unit can my unit be in multiple groups?
  A: No, it must be in a single contiguous group as per Units and Models ( 01.02) and What is Coherency in the core rules. _(core-rules)_
- **FAQ** Q: When a move says that a model or unit must move in a way if it is able, can that requirement force the unit to end their move not in coherency?
  A: No, when a model or unit is making a move it must follow requirements while ending that move in coherency. _(core-rules)_

## 03.03.01 What Is Coherency

- **Commentary**: Coherency prevents models in the same unit from becoming too separated from each other while on the battlefield, ensuring they are set up and end every kind of move as a single group. _(core-rules)_

## 03.04 Engagement

- **FAQ** Q: Does my model or unit become engaged while moving through a enemy units engagement range during a move?
  A: No _(core-rules)_

## 03.04.01 What Is Engagement

- **Commentary**: While opposing models are within each other’s engagement range , they are able to fight in vicious melee, so unless they are seeking to make melee attacks, models should keep out of their foes’ reach. _(rules-appendix)_

## 04.01.01 Models Without Ranged/Melee Weapons

- **Commentary**: A model that does not have any ranged weapons cannot make ranged attacks, and a model that does not have any melee weapons cannot make melee attacks. _(rules-appendix)_

## 04.01.02 Sidearms

- **Commentary**: Some models are equipped with [CLOSE-QUARTERS] weapons in addition to other firearms. Such models can be an exception to the rules in this section, as you may not be able to select all of their weapons to make attacks with. _(rules-appendix)_

## 04.01.03 Multiple Weapon Profiles

- **Commentary**: In the Select Weapons step ( 04.01 ), if a selected weapon has more than one profile, then the controlling player must also select one of those profiles. The selected profile is then used in the Resolve Attacks step ( 04.03 ). Some of these profiles are known as Hunter profiles. Hunter profiles can only target units with the specified keywords . Note that if a unit is equipped with more than one such weapon, a different profile can be selected for each model within that unit. _(rules-appendix)_

## 04.01.04 Attack Characteristics and Abilities

- **Commentary**: When making an attack, that attack is considered to have the same characteristics and abilities as the weapon making that attack. If any modifiers or abilities apply to an attack, those changes apply to the weapon making that attack until that unit’s attack sequence and all effects of those abilities (e.g. [Hazardous] ) have been resolved. Rules that apply to a weapon that modify rolls apply to the attacks made with that weapon. _(rules-appendix)_

## 04.01.05 Selected to Attack

- **Commentary**: Some rules use the term selected to attack . If a unit is selected to fight , selected to shoot or chosen to make attacks, that unit is selected to attack . _(rules-appendix)_

## 04.02 2. Select Targets

- **FAQ** Q: When selecting a target unit can the enemy model that is visible to my model and the enemy model that is in range of my model’s weapon be different enemy models in the same unit?
  A: Yes _(core-rules)_

## 04.02.01 Selecting Targets

- **Commentary**: When shooting or fighting, you can select different targets for each weapon. If you cannot select a target for a weapon, or if you choose not to select a target for a ranged weapon, the model with that weapon will not make attacks with it. _(rules-appendix)_

## 04.02.02 Against An Attack

- **Commentary**: Rules that are triggered ‘against’ certain attacks are triggered after the attacking unit has completed the Select Targets step ( 04.02 ), provided all other qualifiers are met (e.g. concerning the characteristics of the attacking unit or its weapons). Rules that are triggered when an attack is ‘allocated’ to a unit are triggered in step 1 of the Inflict Damage step ( 05.04 ). _(rules-appendix)_

## 04.02.03 Single Target

- **Commentary**: When a model or unit attacks with one or more weapons, if all of the attacks made with those weapons target the same unit, that model or unit is said to be shooting at, fighting or targeting a single target. _(rules-appendix)_

## 04.03 3. Resolve Attacks

- **FAQ** Q: My rule says that "this units ranged attacks have +1 A ", do each of my attacks get an extra attack dice?
  A: No, it increases the A characteristics of the unit's ranged weapons by 1. _(core-rules)_
- **FAQ** Q: When my unit shoots at another unit, how does it work if some models in the target unit are fully visible to some models in my unit, while others are within a terrain area /not fully visible?
  A: For each attacking model in your unit, determine whether the target unit has the benefit of cover, as described in Terrain and Visibility. In this scenario, the target unit will likely have the benefit of cover against some of the attacking models, but not all. This means that, in an example unit where all attacking models are using the same weapon, when you get to the Resolve Attacks step of the Attack Sequence, you will collect dice for attacks made by models against which the target unit has the benefit of cover separately from the dice for attacks made by models against which the target unit does not have the benefit of cover. _(core-rules)_
- **FAQ** Q: If my unit has weapons that are identical in characteristics, but some of those weapons have [PRECISION] and those weapons targeted a unit without the CHARACTER keyword, do I roll all of those weapons together?
  A: Yes, the [PRECISION] ability is not an applicable ability for those attacks as there is no CHARACTER in the target unit for the ability to trigger its rule. _(core-rules)_

## 04.03.01 Identical Attacks

- **Commentary**: Identical attacks are those that have the same BS / WS , S , AP and D characteristics, and which are affected by the same applicable abilities and rules. _(rules-appendix)_

## 04.03.02 Splitting Melee Attacks

- **Commentary**: While selecting targets, if you select more than one unit as the target of a melee weapon, you must split that weapon’s attacks between those target units. To do so, declare how many of that weapon’s attacks will be made against each unit (you must declare at least one attack per unit targeted). In the Gather Attack Dice step , for each weapon that is splitting its attacks, only gather a number of attack dice for that weapon equal to the number of attacks you declared would be made against that target with that weapon. _(rules-appendix)_

## 04.03.03 Target No Longer Eligible Or Viable

- **Commentary**: If a unit that was an eligible target for a rule or attack when it was selected stops being an eligible target (for example, because a rule enables it to make an out-of-phase move that takes it out of range), the controlling player can select new targets. _(rules-appendix)_

## 04.03.04 Shot

- **Commentary**: When all of the attacks made with a ranged weapon have been resolved, that weapon has shot. When all of a model’s ranged weapons have shot, that model has shot. When all models in a unit that are making ranged attacks have resolved all of those attacks, that unit has shot. If a unit was selected to shoot and none of the models in it make any attacks, it has not shot. _(rules-appendix)_

## 04.03.05 Fought

- **Commentary**: When all of the attacks made with a melee weapon have been resolved, that weapon has fought. When all of a model’s selected melee weapons have fought, that model has fought. When all models in a unit that are making melee attacks have resolved all of those attacks, that unit has fought. If a unit was selected to fight and none of the models in it make any attacks, it has not fought. _(rules-appendix)_

## 04.03.06 Finished Making Its Attacks

- **Commentary**: When all of an attacking unit’s attacks have been resolved, it has finished making its attacks, and that unit has attacked. _(rules-appendix)_

## 05.01 1. Hit Roll

- **FAQ** Q: My attack has a rule that means it results in a critical hit on a hit roll of 4+. Does this work when snap shooting?
  A: Unless otherwise stated, no: when snap shooting, each attack only hits on a roll of 6. _(core-rules)_
- **FAQ** Q: My attack has a rule that means it results in a critical hit on a hit roll of 4+, and I would otherwise need a 5+ to hit. Does a 4+ hit?
  A: Yes, except when snap shooting: when snap shooting, each attack only hits on a roll of 6. _(core-rules)_

## 05.01.01 Critical Hits and Critical Wounds

- **Commentary**: Critical hits are still hits, and critical wounds are still wounds. In addition, other rules can be triggered by a critical hit or a critical wound , such as [LETHAL HITS] and [DEVASTATING WOUNDS] ( 24 ). _(core-rules)_

## 05.02.01 Multiple Toughness Characteristics

- **Commentary**: When resolving attacks that target a unit in which the models have two or more different T characteristics, follow the first instruction that applies from below: If the target unit is an attached unit, use the highest T characteristic amongst bodyguard models in that unit that are on the battlefield. Use the highest T characteristic amongst models in that unit that are on the battlefield. _(rules-appendix)_

## 05.03 3. Save Rolls

- **FAQ** Q: When declaring the allocation order of groups in my unit I have more than one non- CHARACTER groups that contain a model with a missing wound, how must I select the order?
  A: Those groups can be selected in an order of your choosing but must be in an order that makes them come before any non- CHARACTER groups that do not contain a model with a missing wound. _(core-rules)_
- **FAQ** Q: I have a unit being attacked with weapons that will modify some of their save rolls to be worse then 6 should I make those save rolls?
  A: Yes, because other models in your unit may have Sv’s that are better those models you’ve mentioned, this means that enough save rolls could be allocated to the those models that the rest of the results are not greater then the Sv’s of the other models in your unit. _(core-rules)_
- **FAQ** Q: Can I group or allocate a wound to a destroyed model?
  A: No. _(core-rules)_

## 05.03.01 Saving Throw

- **Commentary**: The term ‘saving throw’ is the same as save roll . _(core-rules)_

## 05.03.02 Attacks Modified during Hit and Wound rolls

- **Commentary**: Some attacks may be modified as a result of the values of hit / wound rolls made for those attacks. When this happens, split those attacks into attack pools based on their new identical attack profiles. The active player can decide which attack pool to resolve first for steps 05.03 and 05.04 Once those steps have been completed for that attack pool, the active player can decide the next pool to resolve and repeat until all new attack pools are resolved. _(core-rules)_

## 05.04 4. Inflict Damage

- **FAQ** Q: Fight On Death ( 05.04.05) requires models awaiting such an ability to stay on the battlefield until their unit has attacked (or until the end of the phase). How do these models function while this is the case?
  A: Models awaiting a Fight On Death ability are still present on the battlefield for all rules purposes. This includes (but is not limited to) the following regarding such models: They can be measured to by friendly/enemy abilities. They can be considered visible to friendly/enemy models where relevant. They can use their datasheet abilities. They can be targeted by stratagem s. Enemy units can still be engaged with them (which may restrict the opposing player’s consolidation / pile-In moves made as part of an overrun fight). _(core-rules)_
- **FAQ** Q: In what step during the attack sequence do I roll for Feel No Pain?
  A: In the Resolve Damage step of the Inflict Damage step ( 05.04). _(core-rules)_

## 05.04.01 Current Allocation Group

- **Commentary**: The first group in the allocation order begins as the current group. Once all models in an allocation group are destroyed , the next group in the allocation order becomes the current one. _(rules-appendix)_

## 05.04.02 Modifying Damage

- **Commentary**: See Modifiers ( 02.02.01 ). _(rules-appendix)_

## 05.04.03 Suffers Damage

- **Commentary**: If an attack reaches the Resolve Damage step of the attack sequence ( 05.04 ), the model that attack was allocated to has suffered damage, even if that model subsequently uses a rule to ignore the wounds inflicted or it uses a rule that means those wounds are not lost. See Also Modifying Dice Rolls 01.05.03 Modified Characteristics 02.02.01 Random Characteristics 02.02.03 Current Allocation Group 05.04.01 Modifying Damage 05.04.02 Suffers Damage 05.04.03 Destroyed 05.04.04 Fight On Death 05.04.05 Measuring To A Destroyed Model Or Unit 05.04.06 _(core-rules)_

## 05.04.04 Destroyed

- **Commentary**: Throughout a battle, models will suffer damage, lose wounds and be destroyed . When every model in a unit has been destroyed , that unit is destroyed . When a model is destroyed , first resolve any rules that are triggered when it is destroyed , then it is removed from the battlefield. If any such rules apply, and if the model was destroyed as the result of an attack, unless otherwise stated, those rules are only resolved and that model is only removed after the attacking unit’s attacks have been resolved. Unless otherwise stated, destroyed models and units cannot use abilities or be selected or targeted by rules. Some rules only trigger if an enemy model or unit was destroyed by you, or by a model or unit from your army. This means that the enemy model or unit was destroyed by an attack made by a model from your army, or by a player rule you have. Enemy models or units that are destroyed by any other means are not destroyed by you, or by a model or unit from your army. _(rules-appendix)_

## 05.04.05 Fight On Death

- **Commentary**: Some rules enable models to attack after they have been destroyed . When a model under such an effect is destroyed , do not remove it from play. Those models will stay on the battlefield until their unit is selected to attack and has attacked, or until the end of the phase (whichever comes first). Any rules triggered by those models being destroyed are resolved, and then those destroyed models are removed. If a rule instructs a destroyed model to fight immediately after the attacking unit, instead that model is not removed from the battlefield until that model’s unit has fought, or until the end of the phase (whichever comes first). This allows the models in the unit to fight all at once, and stratagems that target that unit will also affect that destroyed model. _(rules-appendix)_

## 05.04.06 Measuring To A Destroyed Model Or Unit

- **Commentary**: When a player has to measure the distance to a destroyed model, that player can measure to any point occupied by that model’s base (or any part of that model if it does not have a base or is a VEHICLE , excluding WALKER models that have a base) before it was destroyed . When a player has to measure the distance to a destroyed unit, they measure to the last model destroyed in that unit. _(rules-appendix)_

## 06.01 Visibility

- **FAQ** Q: When checking line of sight from one model to another, is this drawn between the bases of those models, or between any part of them?
  A: Line of sight is drawn from any part of the observing model to any part of the model being observed. _(core-rules)_
- **FAQ** Q: When a model overhangs the edge of the battlefield, how does that affect its visibility?
  A: That model’s controlling player can draw line of sight from any part of that model that is not overhanging the edge of the battlefield. Their opponent can draw line of sight to any part of that model. _(core-rules)_

## 06.01.01 Describing Visible Units

- **Commentary**: When a rule references a visible unit but does not state which units that unit must be visible to, it must be visible to the unit that is using that rule. Example: You target a friendly unit with a stratagem that says ‘select one visible enemy unit’. That enemy unit must be visible to the friendly unit you targeted with the stratagem. _(core-rules)_

## 06.02 Mortal Wounds

- **FAQ** Q: I have a rule that triggers when a mortal wound is allocated to a model, when does this happen?
  A: When you select a model in the Select Model step of Mortal Wounds ( 06.02). _(core-rules)_

## 06.02.01 Normal Damage

- **Commentary**: Normal Damage is damage that was inflicted on a model as a result of a weapon’s D characteristic, rather than by other means such as mortal wounds . Mortal wounds dealt in addition to normal damage from an attack are part of that same attack. _(rules-appendix)_

## 06.03 Hazard Rolls

- **FAQ** Q: I failed hazard rolls from [Hazardous] weapons, do those mortal wounds have to be allocated to the models with the [HAZARDOUS] weapons?
  A: No, you allocate the mortal wounds to the unit as per Mortal Wounds ( 06.02). (This represents Bob the guardsmen picking up his fallen squad mates plasma gun or that the twisting power of James the Chaos Sorcerer pulling his followers into the warp.) _(core-rules)_
- **FAQ** Q: If a rule says my unit must make a hazard roll does every model in the unit make a hazard roll?
  A: No, the unit would make 1 single hazard roll. _(core-rules)_

## 06.03.01 Hazardous Test

- **Commentary**: The term ‘Hazardous test’ is the same as hazard roll . _(core-rules)_

## 07.01 1. Start of Battle Round

- **Errata** CP Generated by a Warlord: When a rule states that 'At the start of the battle round, if a model with this ability is your WARLORD, gain 1CP.' you do not gain the 1CP while your WARLORD is destroyed. _(core-rules)_

## 07.02.01 Out Of Phase Rules

- **Commentary**: Some rules allow a model or unit to make a move, shoot, declare a charge or fight outside of the normal turn sequence. When using these out-of-phase rules, you cannot use any other ‘phase-locked’ rules; that is, any other rule that explicitly states the phase in which that rule applies. Example: In your opponent’s Movement phase, you target a friendly unit with the Fire Overwatch stratagem. That unit has an ability which is used ‘In your Shooting phase, after this unit has shot’. Because Fire Overwatch is phase-locked to your opponent’s Shooting phase, that ability is not triggered. _(rules-appendix)_

## 07.02.02 Battle Round/Turn/Phase Definitions

- **Commentary**: Start of Battle Round/Turn/Phase: If a rule is triggered at the start of the battle round/turn/phase, it is triggered at the start of every battle round/turn/phase. The Turn/the Phase: If a rule is triggered during the turn/phase instead of during your turn/phase or your opponent’s turn/phase, it is triggered in both players’ turn/phase. Example : If a rule states ‘At the end of the Movement phase, this model heals 1 wound’, that rule triggers at the end of your Movement phase and at the end of your opponent’s Movement phase. _(rules-appendix)_

## 08.02.01 Command Points

- **Commentary**: Command Points are a valuable resource you can spend to use stratagems ( 15 ). The Gain Core CP step ensures that both players gain 1CP each turn. While these are termed Core CP here, they are Command Points like any other. Other rules sometimes mention ‘Core CP’ when referring to these Command Points. _(rules-appendix)_

## 08.03.01 Multiple Battle-shock Rolls

- **Commentary**: In the Battle-shock step ( 08.03 ), unless otherwise stated, no more than one battle-shock roll can be made by each unit. If for any reason a unit must make a battle-shock roll in this step before one it is required to make for being battle-shocked or at or below half-strength , that unit does not also have to make the battle-shock roll for being battle-shocked or at or below half-strength . _(rules-appendix)_

## 09.02.01 Selecting Units To Move

- **Commentary**: When the Move Units step ends, the active player must have selected all of their units to make a move with, including those in strategic reserves . This means that before the phase ends, every unit in their army will have been selected to make a move, even if it is to remain stationary ( 09.04 ). Any units the active player does not select a move type for during this step will remain stationary . _(rules-appendix)_

## 09.02.02 Selecting Modes

- **Commentary**: Some rules instruct you to select a mode, such as fall-back moves ( 09.07 ). Modes are mutually exclusive, and you must assess each one in the order presented. When making a move, if your unit does not meet the conditions of any of the modes, it cannot make that move. Sometimes a mode will be mandatory if applicable (e.g. consolidation modes , 12.08 ), but in the case of fall-back moves , ordered retreat is not mandatory, so you could select desperate escape instead. Many move types state conditions you must meet while/after moving. Those that are labelled with a mode name only apply if you selected that mode; those not labelled with a mode name always apply. _(rules-appendix)_

## 09.02.03 Reinforcements Step

- **Commentary**: Rules that say they happen during the Reinforcements step happen during the Move Units step. _(rules-appendix)_

## 09.05.01 More Than One Normal Move in a Phase

- **Commentary**: A unit cannot make more than one Normal Move in a phase. _(rules-appendix)_

## 09.07.01 Desperate Escape

- **Commentary**: If a stratagem or ability forces a unit to make a Desperate Escape test , that unit: Must make one hazard roll for each model in that unit. Must make a battle-shock roll. Desperate Escape Test Some rules may reference the term ‘Desperate Escape test’. In all instances this means the hazard rolls made for the desperate escape mode of a fall-back move. Abilities that subtract from a unit’s Desperate Escape test instead subtract from those hazard rolls. If a stratagem or ability instructs a unit to make a Desperate Escape test, that unit: Must use the desperate escape mode when it is selected to make a fall-back move. Must make one hazard roll for each model in that unit. Must make a battle-shock roll. Example 1: A battle-shocked unit makes a fall-back move away from a unit of Bloodletters that have the Bane of Cowards ability. As a result of Bane of Cowards, because the unit making the fall-back move is battle-shocked, the hazard rolls they make as part of their desperate escape will be at -1. Example 2: If an ability allows a unit to re-roll Desperate Escape tests, that unit can re-roll hazard rolls made for the desperate escape mode of a fall-back move. Selecting Modes Some rules instruct you to select a mode, such as fall-back moves. Modes are mutually exclusive, and you must assess each one in the order presented. When making a move, if your unit does not meet the conditions of any of the modes, it cannot make that move. Sometimes a mode will be mandatory if applicable (e.g. consolidation modes, 12.08), but in the case of fall-back moves, ordered retreat is not mandatory, so you could select desperate escape instead. Many move types state conditions you must meet while/after moving. Those that are labelled with a mode name only apply if you selected that mode; those not labelled with a mode name always apply. _(core-rules)_

## 10.02 2. Shoot

- **FAQ** Q: Can I select a unit to shoot or fight if it doesn’t have melee or ranged weapons?
  A: Yes, it just makes no attacks and then the fight type or shoot type is resolved. _(core-rules)_

## 11.02 2. Charge Step

- **FAQ** Q: When a rule instructs you to perform a charge outside of the charge phase, do I resolve step 2 and 3 of the Charge step ( 11.02)?
  A: Yes _(core-rules)_

## 11.02.01 Failed Charges

- **Commentary**: Note that in the absence of modifiers to the charge roll , a result of 2 (a double 1) is never sufficient for a unit to complete a charge move , as a unit cannot be within engagement range (2") when it attempts a charge . Such a roll would therefore result in a failed charge , and the unit would not move. _(rules-appendix)_

## 11.03 3. End of Charge Phase

- **Errata** 12.08 - Consolidation Move, After Moving Section, Ongoing Consolidation: Change to: Each model that started this move engaged with an enemy unit must still be engaged with that enemy unit. If one or more enemy units engaged with your unit have not been selected to fight this phase, your opponent must select each of those units, one at a time; when each is selected, it becomes eligible to fight and is selected to fight _(core-rules)_
- **FAQ** Q: If a rule modifies how far a unit or model can move during a pile-in move or consolidation move does it also change the distance of the target units?
  A: No _(core-rules)_
- **FAQ** Q: If a rule allows my unit to pile-in or consolidate an extra distance in the Fight phase, when can I use that rule?
  A: For pile-in moves, during the Pile-in step ( 12.02), and for consolidation moves, during the Consolidate step ( 12.07) of the Fight phase. _(core-rules)_
- **FAQ** Q: If I have a rule that says my unit can move up to 6" when it makes a pile-in move or consolidation move, does this also mean it changes the maximum distance of those moves to 6"?
  A: Yes _(core-rules)_

## 12.04 3. Fight Step

- **FAQ** Q: Can I select a unit to shoot or fight if it doesn’t have melee or ranged weapons?
  A: Yes, it just makes no attacks and then the fight type or shoot type is resolved. _(core-rules)_

## 12.04.01 Eligible to fight, but unable to fight

- **Commentary**: During the Fight sequence, when the sequence returns to a player to select a unit to fight, if all of that player’s units that are eligible to fight are more than 5" from all enemy units, that player can instead choose to pass and return the sequence to their opponent to select a unit. If both players pass in succession, or if one player passes when their opponent has no remaining units that are eligible to fight , the Fight step ends. Designer’s Note: Occasionally, all of a unit’s targets will be destroyed before they have had a chance to fight, with no other targets close enough to engage with a pile-in move. In such cases, a player can choose to pass and wait to see if another enemy unit ends a pile-in move close enough to be attacked later in the phase. _(rules-appendix)_

## 13.01 Placing Terrain

- **FAQ** Q: Are models that are within the boundary of a terrain area, but not on the ground floor of a terrain area (e.g. overhanging parts of FRAME VEHICLES or models on terrain features that are within that terrain area) within that terrain area?
  A: Yes _(core-rules)_

## 13.02.01 Creating Your Own Battlefield

- **Commentary**: Don’t worry if your battlefield doesn’t match a mission’s terrain category requirements; just do the best with the terrain features you have. If a mission does not provide you with guidance, it will be up to the players to decide how to create their battlefield. When doing so, keep in mind that dense terrain features have the greatest impact on visibility and movement. Battlefields with too few dense terrain features can advantage armies that rely on shooting, or disadvantage armies that rely on melee. Also remember to leave sufficient room around dense terrain features for larger models such as MONSTERS/VEHICLES to manoeuvre, especially near the edges of the battlefield. _(rules-appendix)_

## 13.06.01 Solid Terrain and Movement

- **Commentary**: If a terrain feature has the Solid rule ( 13.11 ), as dense terrain features do, a model cannot end a move such that any part of it is through any enclosed part of that terrain feature that is 3" or less from ground level – not even through small openings such as doors and windows. This ensures that protruding elements of models cannot be used to circumvent the visibility restrictions of the Solid rule. _(rules-appendix)_

## 13.08 Benefit of Cover

- **FAQ** Q: When my unit shoots at another unit, how does it work if some models in the target unit are fully visible to some models in my unit, while others are within a terrain area /not fully visible?
  A: For each attacking model in your unit, determine whether the target unit has the benefit of cover, as described in Terrain and Visibility. In this scenario, the target unit will likely have the benefit of cover against some of the attacking models, but not all. This means that, in an example unit where all attacking models are using the same weapon, when you get to the Resolve Attacks step of the Attack Sequence, you will collect dice for attacks made by models against which the target unit has the benefit of cover separately from the dice for attacks made by models against which the target unit does not have the benefit of cover. _(core-rules)_

## 13.09 Hidden

- **Errata** 13.09 - Change to First Bullet Point: Change to: ‘That model has the INFANTRY/BEASTS/SWARM keyword and is within a terrain area that contains one or more light/dense terrain features.’ _(core-rules)_

## 13.09.01 Hidden and the First Turn

- **Commentary**: During the first turn, conditions that require something not to have happened during the previous turn are true. For the Hidden rule, this means that during the first turn a unit has not made ranged attacks during the previous turn. _(core-rules)_

## 13.11.01 Gone to Ground

- **FAQ** Q: If a rule refers to an ‘objective marker’, does this mean an ‘ objective’?
  A: Yes (excluding rules in the Core Rules)'. _(core-rules)_
- **Commentary**: Hidden models that are concealed by dense terrain features gain an extra benefit while they have gone to ground . A model has gone to ground while all of the following apply: That model is hidden. That model is not fully visible to the attacking model due to one or more intervening dense terrain features. That model’s unit did not make one or more ranged attacks during this turn or during the previous turn. While a model has gone to ground , subtract 3" from that model’s detection range . Designer’s Note: Units that made ranged attacks in the current or previous turn cannot go to ground , regardless of any abilities that allow them to shoot and remain hidden . _(core-rules)_

## 14.01 Terrain Objectives

- **FAQ** Q: Are models that are within the boundary of a terrain area, but not on the ground floor of a terrain area (e.g. overhanging parts of FRAME VEHICLES or models on terrain features that are within that terrain area) within that terrain area?
  A: Yes _(core-rules)_

## 14.01.01 Objectives Not Within A Terrain Area

- **Commentary**: If the location point of an objective does not coincide with a terrain area , you must denote the location of that objective with a flat, circular marker, 40mm in diameter, centred on that point – this is called an objective marker . Models can move through objective markers and they can end a move on top of objective markers . A model is within range of an objective marker while it is within 3" horizontally and 5" vertically of that objective marker . When measuring distances to and from an objective marker , measure to and from the closest part of it. _(core-rules)_

## 14.02 Level of Control

- **FAQ** Q: When determining control over an objective, can the same model’s OC count towards more than one objective that model is within range of?
  A: Yes. _(core-rules)_

## 14.02.01 Controlling an Objective at the End of a Phase

- **Commentary**: At the end of each phase and turn, the first thing players do (before any other’at the end of the phase/end of the turn’ rules or abilities ) is determine which objectives are controlled by which player. _(core-rules)_

## 14.03 Secured Objectives

- **FAQ** Q: If my unit has taken control of an objective at the end of my movement phase and that unit has as an ability that secures an objective they control, can they secure that objective?
  A: Yes _(core-rules)_
- **FAQ** Q: Can I use the Insane Bravery stratagem on a battle-shocked unit?
  A: No, as a unit’s controlling player cannot target that unit with stratagems ( 01.07). _(core-rules)_

## 15.01 Using Stratagems

- **Errata** Grenades Stratagem: The Grenade Stratagem is the same as the Explosives stratagem. _(core-rules)_
- **Errata** Tank Shock Stratagem: The Tank Shock Stratagem is the same as the Crushing Impact stratagem. _(core-rules)_
- **Stratagem errata**: Errata Show Grenades Stratagem The Grenade Stratagem is the same as the Explosives stratagem. _(core-rules)_
- **Stratagem errata**: Errata Show Tank Shock Stratagem The Tank Shock Stratagem is the same as the Crushing Impact stratagem. _(core-rules)_
- **FAQ** Q: After using an ability that increases the CP cost of a stratagem, must my opponent continue to use the selected stratagem at the increased cost if they have the necessary CP available?
  A: Yes. _(core-rules)_
- **FAQ** Q: After using an ability that increases the CP cost of a stratagem, if my opponent does not have the necessary CP available for the selected stratagem, what happens?
  A: No CP are spent and that stratagem 's effects are not resolved (but that stratagem still counts as having been used this phase). _(core-rules)_
- **FAQ** Q: If a stratagem contains a section that carries an additional CP cost (such as the Into the Fray option of Heroic Intervention), is that additional cost considered to be a modifier?
  A: No, a stratagem that costs 1CP and is making use of an optional +1CP section has an original cost of 2CP. _(core-rules)_

## 15.01.01 Modifying CP Cost

- **Commentary**: Some rules modify the cost of using certain stratagems . In such cases, the following points apply: The CP cost of a stratagem use can never be modified below 0CP. If a rule modifies the CP cost of a stratagem when you use it, but does not specify a duration for that modifier, that modifier only applies to that usage of that stratagem. _(rules-appendix)_

## 15.01.02 Affected By A Stratagem

- **Commentary**: If a unit is selected as the target of a stratagem , it is said to be affected by that stratagem . _(rules-appendix)_

## 15.01.03 Stratagem Definitions

- **Commentary**: Your Opponent’s Stratagems: stratagems that your opponent uses are sometimes referred to as your opponent’s stratagems. Your Stratagems: stratagems that you use are sometimes referred to as your stratagems. Your Unit (in Stratagems): The term ‘your unit(s)’ in the Effect section of stratagems always relates to the unit(s) selected in the Target section of that stratagem, and never refers to any other units from your army. _(rules-appendix)_

## 16.01 Performing Actions

- **FAQ** Q: If a unit has a rule that allows it to start an action when it is battle-shocked can it also continue doing that action if it becomes battle-shocked after starting an action?
  A: Yes _(core-rules)_

## 17.01 Moving Monsters and Vehicles

- **FAQ** Q: While making a move type other than a normal / advance move, can my MONSTER/VEHICLE unit move through friendly units?
  A: Yes. _(core-rules)_

## 17.02 Frame

- **FAQ** Q: Are models that are within the boundary of a terrain area, but not on the ground floor of a terrain area (e.g. overhanging parts of FRAME VEHICLES or models on terrain features that are within that terrain area) within that terrain area?
  A: Yes _(core-rules)_

## 17.03 Shooting at Engaged Monsters and Vehicles

- **Errata** 17.03 - Change to First Sentence: Add the following to the first sentence: ‘(excluding attacks made with [BLAST] weapons)’. _(core-rules)_
- **Errata** 18.05 - Change to Emergency Disembark Move: WHILE MOVING: Set up each model in your unit: Wholly within the set-up distance of that TRANSPORT, and as close as possible to that TRANSPORT. Or: If the above is not possible while remaining unengaged, set up that model wholly within the set-up distance of that TRANSPORT, as close as possible to that TRANSPORT, and engaged. Each model that still cannot be set up is destroyed. _(core-rules)_
- **FAQ** Q: Can a unit that used the rapid disembark mode this turn (e.g. using a Trukk’s Pilin’ Out ability) be targeted with the Heroic Intervention stratagem?
  A: No. _(core-rules)_

## 17.03.01 Shooting While Engaged With Monsters/Vehicles

- **Commentary**: A unit that is engaged with an enemy MONSTER/VEHICLE unit is still not eligible to shoot , and so cannot make ranged attacks against that MONSTER/VEHICLE unit, unless that unit is eligible to shoot while engaged (e.g. because it is using close-quarters shooting ). _(rules-appendix)_

## 18.02 Embarking

- **FAQ** Q: Do a unit's abilities continue to function while they are embarked within a TRANSPORT?
  A: Yes, within the restrictions specified by the ability itself. Embarked units are Not On The Battlefield ( 01.02.04), so any ability requiring visibility or measurement to another unit will fail. Example: Azrael is attached to an Intercessor Squad unit and embarked within a TRANSPORT, and that TRANSPORT is making a shooting attack using the Firing Deck ability. While Azrael’s Supreme Grand Master ability is still technically active, it will have no effect, as the requirements of the ability are not met (the ability affects ‘weapons equipped by models’ in Azrael’s unit, and for the purposes of Firing Deck, the TRANSPORT itself is equipped with those weapons instead). _(core-rules)_
- **FAQ** Q: If a rule says a unit can embark into a TRANSPORT in a turn that unit disembarked, does this ignore the core rules restriction on embarking in a turn that unit made a set up move (see 18.02)?
  A: Yes _(core-rules)_

## 18.02.01 Able To Embark

- **Commentary**: A unit is able to embark if it meets all of the conditions in Embarking ( 18.02 ). Note that one or more of these conditions may be modified by other rules, in which case a unit must satisfy those modified conditions in addition to any unmodified conditions to be able to embark. _(core-rules)_

## 18.03 Disembarking

- **FAQ** Q: If a unit makes any disembark move in a turn (i.e. Disembark move, Emergency Disembark move etc.) has it disembarked that turn?
  A: Yes. _(core-rules)_

## 18.04.01 Rapid Disembark And Limitations

- **Commentary**: When a unit uses the rapid disembark mode after its TRANSPORT makes an ingress move , the models must follow the same rules and restrictions as that TRANSPORT did. For example, if that TRANSPORT had to be set up more than 8" from all enemy units and not within your opponent’s deployment zone, the same applies to the disembarking unit. _(rules-appendix)_

## 19.01 Forming Attached Units

- **FAQ** Q: The Munitorium Field Manual shows my unit can attach to different units then are on it’s datasheet, which do I use?
  A: Use the Munitorium Field Manual. _(core-rules)_

## 19.01.01 Attached Units After Their Bodyguard Unit is Destroyed

- **Commentary**: Some units have rules stating that when the < bodyguard unit in an attached unit is destroyed , leader/support units that were attached to them become separate units with their original starting strengths . When the bodyguard unit in an attached unit affected by such a rule is destroyed , all of those leader/support units remain a single unit for all rules purposes. _(rules-appendix)_

## 19.03 Keywords in Attached Units

- **FAQ** Q: Units have all the keywords of all their models, and attached units have all the keywords of all of their component units. How are destroyed models taken into account for these purposes?
  A: These statements are only true so long as the models possessing those keywords remain part of the unit; destroyed models do not contribute their keywords to their prior unit. Example: The Aspiring Sorcerer model in a unit of Rubric Marines is destroyed; as none of the remaining models in the unit possess the PSYKER keyword, that unit is no longer a PSYKER unit. _(core-rules)_

## 19.04 Abilities in Attached Units

- **FAQ** Q: When does a model’s or unit’s ability in an attached unit apply to all models in that unit?
  A: A rule that applies to’this/that unit’ or’models in this/that unit’ applies to all models in an attached unit. Rules that just apply to one model in an attached unit (for example, a rule that grants a model Feel No Pain or Lone Operative) only apply to that model, not to all models in the attached unit. _(core-rules)_

## 19.04.01 Only In Death Does Duty End

- **Commentary**: Leader and support units often have abilities that make the models they are leading more powerful. In the same way, some bodyguard units’ abilities can enhance the power of those leading them. Abilities in Attached Units ( 19.04 ) means that once the models conferring such effects are destroyed , that attached unit does not continue to benefit from them. Should those models later be revived , however, those abilities will once more apply to their attached unit. _(rules-appendix)_

## 20.01 Placing Units in Strategic Reserves

- **FAQ** Q: If I place units in strategic reserves during the battle, can this exceed the 50% of my points limit for the battle restriction as mentioned in Placing Units in Strategic Reserves ( 20.01)?
  A: Yes. That restriction is applicable before the battle, in the Declare Battle Formations step. _(core-rules)_
- **FAQ** Q: Does the limit to the combined points value of my units in strategic reserves only apply until the start of the first battle round?
  A: Yes. _(core-rules)_

## 20.01.01 Reserves

- **Commentary**: The term ‘Reserves’ is the same as strategic reserves . _(rules-appendix)_

## 20.01.02 Strategic Reserves at the End of the Battle

- **Commentary**: At the end of the final turn, units in strategic reserves are destroyed , but they do not trigger rules that apply when a model is destroyed . _(core-rules)_

## 20.03.01 Set Up As Reinforcements

- **Commentary**: If a rule mentions a unit being set up on the battlefield as Reinforcements , it means a unit that made an ingress move . _(rules-appendix)_

## 21.03 Flying Models

- **FAQ** Q: When do the effects of a FLYING unit taking to the skies apply?
  A: When that unit is selected to make a normal / advance / fall-back / charge move. Note that for an advance/charge move, this means you must declare that a unit will take to the skies before rolling for that advance/charge move. _(core-rules)_

## 22.03.01 Psychic Abilities with a Psychic Level

- **Commentary**: When using psychic abilities with a psychic level , a PSYKER unit cannot use the same psychic ability more than once per phase. _(rules-appendix)_

## 23.04 Charging and Fighting

- **FAQ** Q: When a unit with Firing Deck is equipped with another unit’s weapons, do abilities that affect those weapons while they are equipped by that other unit affect those weapons while they are equipped by the unit with Firing Deck?
  A: No. For example, if a unit of Flash Gitz with the Supa-snazz Dakka upgrade and an attached Big Mek is embarked within a Trukk, when that Trukk uses Firing Deck to equip the Flash Gitz’ Snazzguns, those weapons: Do not benefit from the Flash Gitz’ Finderz Keeperz ability. Do not benefit from the Big Mek’s More Dakka ability. Do not benefit from the Supa-snazz Dakka upgrade. _(core-rules)_
- **FAQ** Q: What does the X" in Lone Operative X " mean?
  A: The X is a placeholder for a number of inches that the ability might appear in a rule with, like Lone Operative 15" where the X has been replaced with 15" _(core-rules)_
- **FAQ** Q: I failed hazard rolls from [Hazardous] weapons, do those mortal wounds have to be allocated to the models with the [HAZARDOUS] weapons?
  A: No, you allocate the mortal wounds to the unit as per Mortal Wounds (06.02). (This represents Bob the guardsmen picking up his fallen squad mates plasma gun or that the twisting power of James the Chaos Sorcerer pulling his followers into the warp.) _(core-rules)_
- **FAQ** Q: If both players have units with the Scouts ability, do they alternate resolving scout moves?
  A: Yes, players alternate resolving any pre-battle rules units from their army may have, starting with the player who will take the first turn. _(core-rules)_
- **FAQ** Q: In what step during the attack sequence do I roll for Feel No Pain?
  A: In the Resolve Damage step of the Inflict Damage step ( 05.04). _(core-rules)_
- **FAQ** Q: If my unit has the Deadly Demise ability and has an ability that allows it to Fight on Death, how do I resolve this?
  A: Fight on Death rules are resolved before Deadly Demise abilities, meaning that your unit’s Deadly Demise will resolve after your unit has fought /at the end of the phase and the relevant models have been removed from the battlefield. _(core-rules)_
- **FAQ** Q: If the [ANTI] ability on my unit is ANTI-NON-MONSTER/VEHICLE does it mean the [ANTI] rule triggers when targeting units that do not have the MONSTER or VEHICLE keyword?
  A: Yes, ANTI-NON- (any keyword) will trigger on any unit that does not have the specified keyword. _(core-rules)_
- **FAQ** Q: Does vertical movement in a unit that has taken to the skies count towards the distance a model has used for the purposes of [Heavy]?
  A: No. _(core-rules)_

## 24.01.01 With The 'X' Ability

- **Commentary**: Some rules affect or require you to select a model or unit with a particular ability. When resolving such rules, any numbers following the ability are irrelevant when determining if such rules apply. Example : If a rule instructs you to select a model from your army with the Deadly Demise ability, you could select a model with the Deadly Demise 1, Deadly Demise D3 or Deadly Demise D6 ability. _(rules-appendix)_

## 24.11.01 Only [EXTRA ATTACKS] weapons

- **Commentary**: If a unit has [Extra Attacks] weapons, it does not need to select weapons without the [EXTRA ATTACKS] ability in order to make attacks with those [EXTRA ATTACKS] weapons. _(rules-appendix)_

## 24.24.01 Attached units and Lone Operative

- **Commentary**: If all models in an attached unit have Lone Operative , that unit will benefit from Lone Operative . If a unit has Lone Operative , but models in that unit have different range values for Lone Operative , the highest value amongst that unit’s models on the battlefield is applied to the whole unit. If an attached unit below starting strength only contains models with Lone Operative , Lone Operative becomes active again. Example: A CHARACTER with Lone Operative is attached to a bodyguard unit that has Lone Operative 15". Lone Operative 15" is therefore used for the whole unit. Example: A CHARACTER with Lone Operative is attached to a bodyguard unit that does not have Lone Operative. Once all of the bodyguard models have been destroyed and only the CHARACTER remains, the CHARACTER’s Lone Operative becomes active again. _(rules-appendix)_

## 24.26.01 Multiple [ONE SHOT] Weapons

- **Commentary**: If a model is equipped with more than one of the same weapon with the [ONE SHOT] ability (e.g. 2 hunter-killer missiles), that model can shoot with each of those weapons once per battle. _(rules-appendix)_

## 24.28.01 Precision and Devastating Wounds

- **Commentary**: Mortal Wounds inflicted by a [PRECISION] attack with the [DEVASTATING WOUNDS] ability are first applied to the CHARACTER group that was selected for those [PRECISION] attacks (if that group is not already destroyed ). _(rules-appendix)_

## 24.37.01 [TORRENT]

- **Commentary**: [TORRENT] weapons cannot have [INDIRECT FIRE] or [PRECISION] . _(rules-appendix)_

## 25.04 Fill Your Army Roster

- **FAQ** Q: Can an attached unit be given an Upgrade?
  A: Yes. _(core-rules)_
- **FAQ** Q: Can a unit have both an Upgrade and an enhancement?
  A: No, units are prevented from having two enhancements, and Upgrades are enhancements. _(core-rules)_
- **FAQ** Q: Are Upgrades enhancements?
  A: Yes, Upgrades are a type of enhancement (but not all enhancements are Upgrades). _(core-rules)_
