# Shooting Phase Audit Tasks

## Tier 1 — Core Rules Compliance (Blocking for Accurate Games)

- [ ] Implement variable attacks and damage rolling for weapons with D3/D6/D3+3 notation
  The code stores `attacks_raw` and `damage_raw` strings (`RulesEngine.gd:1866, 1874`) and has a `_parse_damage()` function (`RulesEngine.gd:2895-2912`) that recognizes D3/D6 notation.
  However, the main resolution path uses `weapon_profile.get("attacks", 1)` and `weapon_profile.get("damage", 1)` which are pre-converted integers.
  The TODO at `RulesEngine.gd:1838` explicitly says: "TODO: Handle complex damage like D6+2 - for now treat as 1".
  Fix: Before resolving each weapon, roll for variable attacks using the `attacks_raw` string. Before applying damage per failed save, roll for variable damage using the `damage_raw` string. Use the existing `_parse_damage()` function.
  Affects weapons like Frag Grenades (D6 attacks), Multi-melta (D6 damage), Plasma Cannon (D3 attacks).
  Files: `RulesEngine.gd` (resolution functions around lines 467-798 and 803-1180), weapon profile loading.

- [ ] Implement ANTI-[KEYWORD] X+ weapon keyword for critical wounds against matching unit types
  Rule: Critical wounds on wound roll of X+ against units with matching keyword (e.g., Anti-Vehicle 4+ scores critical wounds on 4+ vs Vehicles).
  No implementation exists in `RulesEngine.gd`. The wound roll logic is at `RulesEngine.gd:714-733`.
  Need to: parse the ANTI keyword from weapon data (format "Anti-[keyword] X+"), check if the target unit has the matching keyword, and if so, treat wound rolls of X+ as critical wounds (triggering Devastating Wounds if present).
  This affects many common units and is HIGH priority.
  Files: `RulesEngine.gd` — wound roll logic around lines 700-733, weapon keyword parsing.

- [ ] Implement MELTA X weapon keyword for bonus damage at half range
  Rule: MELTA X adds +X to the Damage characteristic when the target is within half the weapon's range.
  No implementation exists in `RulesEngine.gd`.
  Need to: parse the Melta keyword and value from weapon data, check if target is within half range using edge-to-edge measurement, and add the bonus damage when applying damage.
  The range checking infrastructure already exists — `count_models_in_half_range()` at `RulesEngine.gd:500-504` is used for Rapid Fire and can be referenced.
  This is a core weapon type for anti-vehicle (e.g., Multi-melta, Meltagun).
  Files: `RulesEngine.gd` — damage application, range checking functions.

- [ ] Implement TWIN-LINKED weapon keyword for re-rolling wound rolls
  Rule: TWIN-LINKED allows the attacking player to re-roll all failed wound rolls with that weapon.
  No implementation exists in `RulesEngine.gd`. The wound roll logic at `RulesEngine.gd:714-733` simply compares the raw roll against the threshold with no re-roll support.
  Need to: check if the weapon has the Twin-linked keyword, and if so, re-roll any wound rolls that fail (roll < wound_threshold). Only re-roll once per die (cannot re-roll a re-roll).
  This is a common keyword across many weapon profiles.
  Files: `RulesEngine.gd` — wound roll logic around lines 700-733.

## Tier 2 — Important Defensive Rules

- [ ] Implement Stealth ability giving -1 to hit for ranged attacks targeting units where all models have Stealth
  Rule: If every model in a unit has the Stealth ability, ranged attacks targeting that unit subtract 1 from their hit rolls.
  No check for the Stealth keyword exists in `RulesEngine.gd`. The `_resolve_assignment_until_wounds()` function checks for Heavy, BGNT, and user-specified modifiers on the attacker's side but never checks the target for defensive abilities.
  Fix: In the hit modifier calculation section of `_resolve_assignment_until_wounds()` (around `RulesEngine.gd:591-601`), check if all alive models in the target unit have the Stealth keyword, and if so, apply `HitModifier.MINUS_ONE`.
  The `HitModifier` enum and `apply_hit_modifiers()` function exist at `RulesEngine.gd:349-378` and can be reused.
  Files: `RulesEngine.gd` — hit modifier section in `_resolve_assignment_until_wounds()`, and also in `_resolve_assignment()` for the auto-resolve path.

- [ ] Implement Lone Operative ability restricting targeting to within 12 inches
  Rule: Unless part of an Attached unit, a unit with Lone Operative can only be selected as the target of a ranged attack if the attacking model is within 12".
  No check for Lone Operative exists in `get_eligible_targets()` or `validate_shoot()` in `RulesEngine.gd`.
  Fix: In `get_eligible_targets()` (around `RulesEngine.gd:1611-1655`), before adding a target to the eligible list, check if the target has the Lone Operative keyword and is not attached to a bodyguard unit (`attached_to` check). If so, verify that at least one alive model in the actor unit is within 12" of the target using the existing edge-to-edge measurement.
  Also add a check in `validate_shoot()` for consistency.
  Affects characters like Vindicare Assassin and many standalone characters.
  Files: `RulesEngine.gd` — `get_eligible_targets()` and `validate_shoot()`.

- [ ] Implement wound roll modifier system with +1/-1 cap, similar to existing hit roll modifiers
  Rule: Wound rolls can be modified by +1 or -1 (from abilities, auras, stratagems). Like hit roll modifiers, wound roll modifiers are capped at a net +1/-1. An unmodified wound roll of 1 always fails.
  Hit roll modifiers are well-implemented with `HitModifier` enum and `apply_hit_modifiers()` at `RulesEngine.gd:349-378`. No equivalent system exists for wound rolls.
  The wound roll logic at `RulesEngine.gd:714-733` simply compares the raw roll against the threshold with no modifier application.
  The `assignment.modifiers` dictionary supports `hit` modifiers but has no `wound` modifier path.
  Need to: create a `WoundModifier` enum similar to `HitModifier`, add an `apply_wound_modifiers()` function, integrate it into the wound roll comparison, ensure unmodified 1 always fails, and cap net modifier at +1/-1.
  This infrastructure is needed for TWIN-LINKED re-rolls, LANCE keyword, and many unit abilities.
  Files: `RulesEngine.gd` — create new wound modifier system near the existing hit modifier system (lines 349-378), integrate into wound roll logic (lines 714-733).

- [ ] Implement HAZARDOUS weapon keyword causing mortal wounds on roll of 1 after attacking
  Rule: After a unit has attacked with Hazardous weapons, for each Hazardous weapon that was used, roll one D6. On a 1, the bearer suffers 3 mortal wounds (or is destroyed if non-Character/non-Vehicle/non-Monster).
  No implementation exists in `RulesEngine.gd`.
  Need to: after resolving all attacks for a weapon with the Hazardous keyword, roll D6 per model that fired a Hazardous weapon. On a roll of 1, apply 3 mortal wounds to the bearer model. If the bearer is not a CHARACTER, VEHICLE, or MONSTER, it is simply destroyed instead.
  Affects plasma weapons (Plasma Gun, Plasma Cannon, etc.).
  Files: `RulesEngine.gd` — add post-attack Hazardous resolution. `ShootingPhase.gd` — trigger Hazardous checks after weapon resolution completes (around lines 682-764, the sequential weapon resolution section).

- [ ] Implement INDIRECT FIRE weapon keyword for shooting without line of sight
  Rule: Weapons with Indirect Fire can target units not visible to the attacking model. When doing so: -1 to hit roll, unmodified hit rolls of 1-3 always fail (instead of just 1), and the target gains Benefit of Cover.
  No implementation exists in `RulesEngine.gd`.
  Need to: check if the weapon has the Indirect Fire keyword, and if the target is NOT visible (fails LoS check), allow the attack but apply the penalties: -1 to hit (via HitModifier system), unmodified rolls of 1-3 auto-fail, and force Benefit of Cover on the target.
  The LoS check exists at `RulesEngine.gd:1350-1351` via `_check_line_of_sight()`. Currently, failing LoS prevents targeting entirely — need to allow it for Indirect Fire weapons.
  The cover system exists at `RulesEngine.gd:1293-1296`.
  Files: `RulesEngine.gd` — `validate_shoot()`, `get_eligible_targets()`, hit roll logic, and cover application.

- [ ] Enforce Pistol mutual exclusivity — cannot fire both Pistol and non-Pistol weapons on the same model
  Rule: If a model fires a Pistol weapon, it cannot fire any other ranged weapons that turn. Conversely, if a model fires a non-Pistol weapon, it cannot fire Pistol weapons.
  The code correctly restricts Pistol use to engagement range scenarios, but does not enforce mutual exclusivity.
  The validation in `_validate_assign_target()` at `ShootingPhase.gd:180-211` only checks for weapon-split across targets, not for Pistol/non-Pistol mixing on the same model.
  Fix: In the weapon assignment validation, track whether each model has been assigned a Pistol or non-Pistol weapon. Reject assignments that would give a model both types.
  Files: `ShootingPhase.gd` — `_validate_assign_target()` around lines 180-211, weapon assignment tracking.

## Tier 3 — Polish & Multiplayer

- [ ] Implement Overwatch (Fire Overwatch Stratagem) allowing defender to shoot at charging/shooting units
  Rule: The defending player may use the Fire Overwatch stratagem (1CP) to shoot at an enemy unit during the opponent's Shooting, Charge, or Movement phases. Overwatch hits only on unmodified 6s regardless of BS or modifiers.
  Not implemented. Test stubs exist in `test_shooting_phase.gd:312-324` and `test_charge_phase.gd:141-161`.
  This requires: a Stratagem system (new), CP tracking for stratagem spending (extends existing Command Phase CP generation), an interrupt/reaction window in ShootingPhase and ChargePhase, NetworkManager support for cross-player actions during opponent's phase, and a RulesEngine function for Overwatch resolution (hits on 6s only).
  This is a large feature that adds defender agency in multiplayer.
  Files: New stratagem system, `ShootingPhase.gd`, `ChargePhase.gd` (if exists), `NetworkManager`, `RulesEngine.gd`.

- [ ] Implement PRECISION weapon keyword allowing wounds to be allocated to attached Character models
  Rule: When a model with a Precision weapon scores a critical wound (unmodified 6), the attacking player can choose to allocate that wound to an attached Character model instead of the bodyguard unit.
  No implementation exists. Currently attached characters are targeted through the bodyguard unit (`RulesEngine.gd:1611-1613`) with no option to allocate directly.
  Need to: detect critical wounds from Precision weapons, present the attacker with a choice to allocate to the Character, and modify the wound allocation flow accordingly.
  Files: `RulesEngine.gd` — wound allocation logic around lines 3648-3718, `WoundAllocationOverlay.gd`.

- [ ] Add remote player visual feedback for shooting actions (target highlights, range circles, LoS lines)
  When the active player selects a shooter, assigns targets, and resolves attacks, the remote player sees state changes and dice results but NOT the visual feedback (range circles, LoS lines, target highlights).
  The visual feedback is created by `ShootingController.gd` which only runs for the active player.
  Suggestion: Broadcast "SELECT_SHOOTER" and "ASSIGN_TARGET" visual hints to the remote player. The `ShootingController` could listen for remote actions and create simplified visual overlays.
  Files: `ShootingController.gd` — visual creation logic, `NetworkManager` — broadcast additional visual state.

- [ ] Add expected damage preview when hovering weapons over potential targets
  When hovering a weapon over a potential target, show an expected damage preview: "~X hits, ~Y wounds, ~Z unsaved" based on the weapon profile vs target stats.
  The `RulesEngine.gd` already has all the data needed to compute this (BS, weapon S vs target T, AP vs save, damage).
  Need to: create a calculation function that computes expected values without rolling dice, and display the result in a tooltip or overlay near the target.
  Files: `RulesEngine.gd` — new expected damage calculation function. `ShootingController.gd` — UI display on hover.

- [ ] Add animated dice roll visualization replacing text-based dice log
  Currently dice results are shown in a text-based dice log. Both hit and wound rolls appear as numbers.
  Suggestion: Add animated dice roll visualization — show 2D dice sprites rolling and landing. Highlight critical hits (6s) in gold, misses (1s) in red.
  This is impactful for engagement in multiplayer where both players watch the rolls.
  The `dice_rolled` signal already emits dice blocks that can be visualized.
  Files: New dice visualization scene/script, integration with `ShootingPhase.gd` dice_rolled signal.

## Tier 4 — Nice to Have

- [ ] Implement LANCE weapon keyword giving +1 to wound if bearer charged this turn
  Rule: +1 to wound rolls if the bearer's unit made a charge move this turn. Primarily melee but applies to ranged weapons too.
  No implementation exists. Requires the wound modifier system to be implemented first (see wound roll modifier task).
  Need to: check if the attacking unit has the `charged` flag set, and if the weapon has the Lance keyword, apply +1 wound modifier.
  Files: `RulesEngine.gd` — wound roll logic, depends on wound modifier system being in place.

- [ ] Implement ONE SHOT weapon keyword restricting weapon to single use per battle
  Rule: A weapon with One Shot can only be fired once per battle. After firing, it cannot be selected again.
  No implementation exists.
  Need to: track which One Shot weapons have been fired (per model, persisted across turns), and exclude them from weapon selection in subsequent shooting phases.
  Files: `RulesEngine.gd` — weapon eligibility, unit/model state tracking for fired One Shot weapons. `ShootingPhase.gd` — weapon selection filtering.

- [ ] Implement EXTRA ATTACKS weapon keyword for bonus attacks that don't replace normal attacks
  Rule: A weapon with Extra Attacks provides additional attacks on top of the model's normal attacks, rather than being an alternative weapon choice.
  No implementation exists.
  Need to: when a model has a weapon with Extra Attacks, automatically include those attacks in addition to whatever other weapon the model fires, rather than requiring the player to choose between them.
  Files: `ShootingPhase.gd` — weapon assignment logic. `RulesEngine.gd` — attack counting.

- [ ] Implement Go to Ground and Smokescreen stratagems for defender reactions
  Rule: Go to Ground (Infantry) and Smokescreen (SMOKE keyword units) are stratagems the defender can use when targeted. Go to Ground makes the unit go prone for improved cover. Smokescreen grants Benefit of Cover.
  Requires the stratagem system to be built first (see Overwatch task).
  Files: New stratagem system, `RulesEngine.gd` — cover/save modifications.

- [ ] Add shooting phase summary panel showing total hits/wounds/casualties per target after all units have shot
  After all units have shot, show a summary panel with total hits/wounds/casualties per target unit before ending the phase.
  This gives both players a clear picture of the phase's outcome.
  Files: New UI panel scene, `ShootingPhase.gd` — trigger display before phase end.

- [ ] Add shooting line animation and tracer effects from attacker to target during resolution
  During attack resolution, draw a clear animated line or arrow from the shooting unit to its target. Add a brief muzzle flash or tracer effect. Remove after resolution completes.
  An LoS line exists (`los_visual` in `ShootingController.gd:29`) but is used primarily for LoS debugging, not as a persistent shooting visualization.
  Files: `ShootingController.gd` — visual line creation. New particle/animation effects.

- [ ] Add keyboard shortcuts for common shooting phase actions (Space/Enter confirm, Escape cancel, Tab cycle, N skip, E end)
  Keyboard shortcuts for frequent actions: Space or Enter to confirm targets, Escape to deselect/cancel, Tab to cycle through eligible units, N to skip current unit, E to end shooting phase.
  Files: `ShootingPhase.gd` or `ShootingController.gd` — input handling.

## Additional Issues from Audit

- [ ] Expand cover determination beyond ruins terrain to include area terrain, obstacles, woods, craters, barricades
  Currently `check_benefit_of_cover()` at `RulesEngine.gd:1440-1461` only checks for "ruins" terrain type.
  Rule: Benefit of Cover can be granted by ruins, area terrain, obstacles, and other terrain features. Specific conditions apply depending on terrain type (e.g., "within" for Area Terrain, "behind" for obstacles).
  Files: `RulesEngine.gd` — `check_benefit_of_cover()` around lines 1440-1461, terrain type definitions.

- [ ] Fix Devastating Wounds to properly model mortal wounds as distinct damage type with correct spillover
  Per updated 10e rules (post-December 2024 FAQ), Devastating Wounds converts critical wounds into mortal wounds equal to the Damage characteristic. These mortal wounds are allocated AFTER all normal attacks are resolved. Mortal wounds spill over to other models.
  Current implementation at `RulesEngine.gd:3777-3790` applies devastating damage as a pool via `_apply_damage_to_unit_pool()`, which is functionally close but doesn't explicitly model mortal wounds as a distinct damage type.
  Need to verify spillover behavior and FNP interaction edge cases.
  Files: `RulesEngine.gd` — devastating wound handling around lines 700-733 and 3630-3641 and 3776-3790.

- [ ] Add unmodified wound roll of 1 always fails check to wound roll logic
  Rule: An unmodified wound roll of 1 always fails regardless of modifiers.
  Currently no wound modifiers exist so this hasn't been an issue. The code at `RulesEngine.gd:718-733` just checks `if roll >= wound_threshold` which would incorrectly allow a modified 1 to succeed once wound modifiers are added.
  Fix: Add explicit check for unmodified roll == 1 as auto-fail before comparing against threshold. Should be done when wound modifier system is implemented.
  Files: `RulesEngine.gd` — wound roll logic around lines 718-733.

- [ ] Add unmodified save roll of 1 always fails check to auto-resolve save path
  Rule: An unmodified saving throw of 1 always fails.
  The interactive save path in `WoundAllocationOverlay` handles this via the UI. But the auto-resolve path in `_resolve_assignment()` at `RulesEngine.gd:1129` does `if save_roll >= save_needed` without explicitly checking for unmodified 1.
  Fix: Add `if save_roll == 1: failed` check before the threshold comparison in `_resolve_assignment()`.
  Files: `RulesEngine.gd` — `_resolve_assignment()` around line 1129.

- [ ] Sync duplicate resolution paths to prevent rules drift between auto-resolve and interactive paths
  Two parallel resolution functions exist: `_resolve_assignment()` (auto-resolve, `RulesEngine.gd:803-1180`) and `_resolve_assignment_until_wounds()` (interactive, `RulesEngine.gd:467-798`).
  Risk: If a keyword or rule is updated in one path but not the other, they'll produce different results.
  Consider refactoring to share common logic, or at minimum ensure both paths are updated together when adding new keywords/rules.
  Files: `RulesEngine.gd` — both resolution functions.

- [ ] Fix single weapon result dialog to include hit count and total attacks data instead of hardcoded zeros
  In the single-weapon path through `_process_apply_saves()` at `ShootingPhase.gd:1796-1807`, the `last_weapon_result` dictionary has hardcoded zeros for "hits" and "total_attacks".
  The data IS available in the dice log but isn't being extracted.
  Fix: Extract hit count and total attacks from the dice log or resolution results and populate the result dictionary.
  Files: `ShootingPhase.gd` — `_process_apply_saves()` around lines 1796-1807.

- [ ] Fix weapon ID generation to prevent collisions for weapons with similar names
  `_generate_weapon_id()` creates IDs from weapon names (lowered, spaces to underscores). If two different weapons share the same generated ID (e.g., different variants of "Bolt Rifle"), they'd collide.
  Fix: Include additional distinguishing information in the ID (e.g., weapon stats hash, model index, or a unique counter).
  Files: `RulesEngine.gd` or `ShootingPhase.gd` — wherever `_generate_weapon_id()` is defined.

- [ ] Add auto-select weapon for single-weapon units to reduce unnecessary clicks
  If a unit only has one ranged weapon type, auto-assign it when a target is selected. Only show the full weapon assignment UI for units with 2+ weapon types.
  Files: `ShootingPhase.gd` — weapon assignment flow, `ShootingController.gd` — UI logic.

- [ ] Add "Shoot All Remaining" button to auto-process eligible units that haven't shot
  After a unit finishes shooting, add a "Shoot All Remaining" or "Auto-Shoot Remaining" option that iterates through all eligible units, using a default target assignment (e.g., nearest eligible target). Include a confirmation step before executing.
  Files: `ShootingPhase.gd` — phase flow, `ShootingController.gd` — UI button.

- [ ] Show weapon stats (range, S, AP, D, keywords) in target assignment UI panel
  When assigning weapons to targets, show a compact weapon stat line next to each weapon (e.g., "Bolt Rifle: 24\" S4 AP-1 D1 [Rapid Fire 1, Heavy]").
  Files: `ShootingController.gd` — weapon assignment UI panel.

- [ ] Add "Undo Last Assignment" button to weapon assignment UI
  Currently the clear button removes all assignments. Add an "Undo Last" button that removes only the most recent weapon assignment while keeping previous ones.
  Files: `ShootingPhase.gd` — assignment tracking, `ShootingController.gd` — UI button.

- [ ] Add target unit damage feedback with flash effect and death animation when models take damage or die
  Currently casualties are applied and sprites are updated with no transition effect.
  Suggestion: Add a brief damage flash (red tint) when a model takes damage, and a death animation (fade out, fall over, or small explosion particle) when destroyed.
  Files: Model scene scripts, new particle/animation effects.

- [ ] Add range circle visualization showing weapon range and half-range when selecting weapons
  When a weapon is selected, show its range as a translucent circle on the board. Color-code eligible targets inside the range. Show half-range for Rapid Fire and Melta weapons as a dotted inner circle.
  `ShootingRangeVisual` exists at `ShootingController.gd:133-135` as a Node2D container but needs full implementation.
  Files: `ShootingController.gd` — `ShootingRangeVisual` implementation.

- [ ] Enhance wound allocation overlay with pulsing highlight on priority model, health color gradient, and wound counters
  Enhance `WoundAllocationOverlay.gd` with: pulsing highlight on the model that must receive the next wound (priority wounded model), color gradient from green to red on model bases based on health, and small wound counter displayed near each model's sprite.
  Files: `WoundAllocationOverlay.gd`.

- [ ] Add weapon keyword icons next to weapon names in UI (lightning for Lethal Hits, spread for Blast, flame for Torrent, etc.)
  Display small icons next to weapon names in the UI to represent their keywords, making weapon capabilities immediately recognizable without reading text.
  Files: UI scenes for weapon display, new icon assets.

- [ ] Add phase transition animation banner when entering Shooting Phase
  Show a brief phase banner ("SHOOTING PHASE" with an appropriate icon) that fades in and out when entering the phase. Signals phase change clearly to both players.
  Files: Phase transition UI, `ShootingPhase.gd` — trigger on phase entry.

- [ ] Improve save dialog timing reliability for defender on remote client with retry/confirmation mechanism
  The `saves_required` signal triggers the wound allocation overlay. In multiplayer, save data is broadcast in the action result. If the broadcast is delayed or lost, the defender may not see the save dialog.
  The code has defensive logging at `ShootingPhase.gd:601-619` but no explicit retry or confirmation mechanism.
  Files: `ShootingPhase.gd` — save data broadcast, `NetworkManager` — reliable delivery.

- [ ] Sync dice log visibility to remote player in real-time during shooting resolution
  The `dice_rolled` signal emits dice blocks locally. The remote player receives dice results through action result broadcasts, but real-time dice roll display may not be synchronized.
  Files: `ShootingPhase.gd` — dice_rolled signal, `NetworkManager` — dice result broadcasting.
