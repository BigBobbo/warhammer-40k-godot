# Shooting Phase Audit — Rules Compliance & Implementation Review

> Audit of `ShootingPhase.gd` (1,929 lines), `ShootingController.gd` (2,327 lines),
> `RulesEngine.gd` (shooting-related functions, ~2,000 lines), and `WoundAllocationOverlay.gd` (54KB)
> against Warhammer 40,000 10th Edition core rules, with focus on online multiplayer.

---

## Executive Summary

The shooting phase implementation is **the most feature-rich phase** in the codebase, covering the core mechanical loop well: unit selection, target declaration with LoS/range validation, weapon assignment with per-model granularity, hit rolls, wound rolls, interactive save resolution via a wound allocation overlay, damage application, and sequential weapon resolution for units with multiple weapon types. Several weapon keywords are fully implemented (Assault, Heavy, Rapid Fire, Pistol, Blast, Torrent, Lethal Hits, Sustained Hits, Devastating Wounds) and the system correctly handles Big Guns Never Tire, invulnerable saves, cover, and Feel No Pain.

However, **several weapon keywords are missing entirely**, there are **rules-compliance gaps** in targeting restrictions, modifier handling, and damage calculation, and the **multiplayer experience lacks feedback** in several areas. There are also significant quality-of-life and visual improvements that would make the phase more usable.

---

## 1. Rules Compliance — What's Implemented Correctly

| Rule | Status | Location |
|------|--------|----------|
| Eligibility: cannot shoot if unit Advanced (except Assault weapons) | ✅ | `ShootingPhase.gd:1027-1029` — checks `flags.advanced`, delegates to `_unit_has_assault_weapons()` |
| Eligibility: cannot shoot if unit Fell Back | ✅ | `ShootingPhase.gd:1032-1033` — checks `flags.fell_back` |
| Eligibility: cannot shoot twice per phase | ✅ | `ShootingPhase.gd:1022-1023` — checks `flags.has_shot` |
| Eligibility: embarked units cannot shoot directly | ✅ | `ShootingPhase.gd:1014-1015` — checks `embarked_in` |
| ASSAULT keyword: units that Advanced can only fire Assault weapons | ✅ | `RulesEngine.gd:1224-1225` — `validate_shoot()` checks `is_assault_weapon()` |
| HEAVY keyword: +1 to hit if remained stationary | ✅ | `RulesEngine.gd:591-594` — checks `flags.remained_stationary` |
| RAPID FIRE keyword: extra attacks at half range | ✅ | `RulesEngine.gd:500-504` — `count_models_in_half_range()` with edge-to-edge distance |
| PISTOL keyword: can fire in engagement range, only at engaged enemies | ✅ | `RulesEngine.gd:1230-1232, 1636-1654` — full Pistol targeting logic |
| BLAST keyword: +1 attack (6-10 models), +2 attacks (11+), min 3 attacks vs 6+ | ✅ | `RulesEngine.gd:2194-2251` — `calculate_blast_bonus()` and `calculate_blast_minimum()` |
| BLAST restriction: cannot target units in engagement with friendlies | ✅ | `RulesEngine.gd:2279-2308` — `validate_blast_targeting()` |
| TORRENT keyword: auto-hits, no critical hits possible | ✅ | `RulesEngine.gd:554-581` — complete Torrent logic including no-crit interaction |
| LETHAL HITS keyword: critical hits (unmodified 6) auto-wound | ✅ | `RulesEngine.gd:710-717` — auto-wounds tracked separately |
| SUSTAINED HITS keyword: bonus hits on critical hits (fixed or DX) | ✅ | `RulesEngine.gd:640-655` — `roll_sustained_hits()` with D3/D6 support |
| DEVASTATING WOUNDS keyword: critical wounds bypass saves entirely | ✅ | `RulesEngine.gd:700-733, 3630-3641` — mortal wound conversion, unsaveable damage |
| Lethal Hits + Sustained Hits interaction (correct per rules) | ✅ | `RulesEngine.gd:710-718` — auto-wounds don't get sustained, bonus hits roll normally |
| Torrent + Lethal Hits interaction (Lethal never triggers with Torrent) | ✅ | `RulesEngine.gd:554-570` — explicitly noted in code |
| Big Guns Never Tire: Monsters/Vehicles shoot in engagement range | ✅ | `ShootingPhase.gd:1057-1058, RulesEngine.gd:1651-1655` |
| Big Guns Never Tire: -1 to hit with non-Pistol weapons | ✅ | `RulesEngine.gd:596-601` — `bgnt_penalty_applied` modifier |
| Strength vs Toughness wound chart (2+/3+/4+/5+/6+) | ✅ | `RulesEngine.gd:1275-1286` — `_calculate_wound_threshold()` matches 10e table |
| Critical hits: unmodified 6 always hits | ✅ | `RulesEngine.gd:617-624` — checks `unmodified_roll == 6` before modifiers |
| Critical wounds: unmodified 6 always wounds | ✅ | `RulesEngine.gd:721-732` — tracked for Devastating Wounds |
| Unmodified 1 always misses (hit rolls) | ✅ | `RulesEngine.gd:617` — explicit auto-miss on unmodified 1 |
| Hit modifier cap: net +1/-1 max | ✅ | `RulesEngine.gd:369-374` — `clamp(net_modifier, -1, 1)` |
| Invulnerable saves: unaffected by AP | ✅ | `RulesEngine.gd:1305-1312` — `_calculate_save_needed()` compares armour vs invuln |
| Cover: +1 to armour save | ✅ | `RulesEngine.gd:1295-1296` — applied in save calculation |
| Cover: 3+ or better save doesn't benefit vs AP 0 | ✅ | `RulesEngine.gd:1293-1294` — explicit check |
| Saves can never be better than 2+ | ✅ | `RulesEngine.gd:1303` — `armour_save = max(2, armour_save)` |
| Wound allocation: previously wounded models must receive attacks first | ✅ | `RulesEngine.gd:3648-3718` — `_get_save_allocation_requirements()` prioritizes wounded |
| Feel No Pain: rolls per wound, prevents on threshold+ | ✅ | `RulesEngine.gd:3938-3952` — `roll_feel_no_pain()` |
| Feel No Pain: applies even to devastating wounds | ✅ | `RulesEngine.gd:3776-3790` — FNP rolled before DW damage applied |
| Range check: edge-to-edge with shape-aware measurement | ✅ | `RulesEngine.gd:1341-1348` — uses `Measurement.model_to_model_distance_px()` |
| Line of sight: base-aware true LoS | ✅ | `RulesEngine.gd:1350-1351` — `_check_line_of_sight()` |
| Target selection: cannot target friendly units | ✅ | `RulesEngine.gd:1247-1248` — owner check in `validate_shoot()` |
| Attached characters: targeted through bodyguard unit | ✅ | `RulesEngine.gd:1611-1613` — `attached_to` check in `get_eligible_targets()` |
| Save improvement cap: never improved by more than +1 | ✅ | `RulesEngine.gd:1299-1301` — cap applied |
| Sequential weapon resolution: resolve one weapon type at a time | ✅ | `ShootingPhase.gd:682-764` — full sequential weapon resolution with pauses |
| Transport firing deck support | ✅ | `ShootingPhase.gd:1328-1378` — firing deck dialog for embarked units |
| Multiplayer: deterministic dice via seeded RNG | ✅ | `RulesEngine.gd:326-344` — `RNGService` class with session seed |
| Multiplayer: save data broadcast for interactive saves | ✅ | `ShootingPhase.gd:628-631` — `save_data_list` included in action results |
| Multiplayer: weapon order sync for sequential resolution | ✅ | `ShootingPhase.gd:409-412` — `confirmed_assignments` in result payload |

---

## 2. Rules Compliance — What's Missing or Incomplete

### 2.1 ~~CRITICAL: Targeting Units in Engagement Range of Friendly Units — Not Implemented~~ FIXED

**Rule:** Units cannot shoot at enemy units that are within engagement range of friendly units, UNLESS the target is a MONSTER or VEHICLE (Big Guns Never Tire). This is a general restriction that applies to ALL weapons (not just Blast).

**Status:** FIXED. Added `_is_target_in_friendly_engagement()` helper in `RulesEngine.gd` and checks in both `get_eligible_targets()` and `validate_shoot()`. MONSTER/VEHICLE targets are exempt per Big Guns Never Tire.

### ~~2.2 CRITICAL: Overwatch (Fire Overwatch Stratagem) — Not Implemented~~ DONE

**Rule:** The defending player may use the Fire Overwatch stratagem (1CP) to shoot at an enemy unit that is targeting one of their units. Overwatch hits only on unmodified 6s. Can be used during the opponent's Shooting, Charge, or Movement phases.

**Status:** IMPLEMENTED. `StratagemManager.gd` defines `fire_overwatch` stratagem with `overwatch_shoot` action type. Full stratagem system now exists with CP tracking and integration into the shooting flow.

### 2.3 CRITICAL: Missing Weapon Keywords — Several Not Implemented

The following weapon keywords exist in 10th edition rules but have **no implementation** in `RulesEngine.gd`:

| Missing Keyword | Rule Effect | Priority |
|----------------|-------------|----------|
| ~~**ANTI-[KEYWORD] X+**~~ | ~~Critical wounds on wound roll of X+ against units with matching keyword (e.g., Anti-Vehicle 4+ scores critical wounds on 4+ vs Vehicles)~~ | **FIXED** — `get_anti_keyword_data()`, `get_critical_wound_threshold()`, `unit_has_keyword()` in `RulesEngine.gd`; applied in all 3 wound resolution paths |
| **MELTA X** | +X damage at half range | HIGH — core weapon type |
| **TWIN-LINKED** | Re-roll wound rolls | HIGH — common keyword |
| **HAZARDOUS** | After attacking, roll D6 per Hazardous weapon; on 1, bearer suffers 3 MW (or removed if non-Character/Vehicle/Monster) | MEDIUM — affects plasma weapons |
| **INDIRECT FIRE** | Can target without LoS; -1 to hit, unmodified 1-3 always fails, target gains Benefit of Cover | MEDIUM — key for artillery |
| ~~**IGNORES COVER**~~ | ~~Target cannot have Benefit of Cover~~ | **FIXED** — runtime logic added in `has_ignores_cover()`, `prepare_save_resolution()`, and auto-resolve path |
| **PRECISION** | Can allocate wounds to attached Character models instead of bodyguard | MEDIUM — important for character sniping |
| **LANCE** | +1 to wound if bearer charged this turn | LOW (shooting only) — primarily melee, but applies to ranged too |
| **ONE SHOT** | Weapon can only be fired once per battle | LOW — niche |
| **EXTRA ATTACKS** | Bonus attacks that don't replace normal attacks | LOW — niche |

**Note:** "IGNORES COVER" runtime logic has been implemented. The `has_ignores_cover()` function checks weapon keywords/special_rules, and both `prepare_save_resolution()` (interactive path) and `_resolve_assignment()` (auto-resolve path) skip cover when the weapon has this keyword.

### 2.4 ~~HIGH: Variable Attacks and Damage Not Rolled — Always Fixed~~ FIXED

**Rule:** Many weapons have variable attacks (e.g., D6, D3+3) and variable damage (e.g., D6, D3+1). These should be rolled each time the weapon fires.

**Status:** FIXED. All three shooting resolution paths now roll variable attacks per model and variable damage per failed save using `roll_variable_characteristic()`. Both `_resolve_assignment_until_wounds()` (interactive path) and `_resolve_assignment()` (auto-resolve path) roll variable attacks per model. `apply_save_damage()` and `WoundAllocationOverlay._roll_save_for_model()` roll variable damage per failed save. Legacy weapon profiles now include `attacks_raw`/`damage_raw` fields, and the weapon profile builder uses average (rounded up) for non-integer stat fallbacks instead of defaulting to 1. The dice log UI displays variable attack/damage roll results in the ShootingController.

### 2.5 HIGH: Wound Roll Modifiers — Not Implemented

**Rule:** Wound rolls can be modified by +1 or -1 (from abilities, auras, stratagems). Like hit roll modifiers, wound roll modifiers are capped at a net +1/-1. An unmodified wound roll of 1 always fails.

**Current state:** Hit roll modifiers are well-implemented with `HitModifier` enum and `apply_hit_modifiers()` (`RulesEngine.gd:349-378`). However, there is **no equivalent system for wound roll modifiers**. The wound roll logic (`RulesEngine.gd:714-733`) simply compares the raw roll against the threshold — no modifier application, no reroll support, no capping. The `assignment.modifiers` dictionary supports `hit` modifiers but has no `wound` modifier path.

**Impact:** Any ability that grants +1 or -1 to wound rolls (e.g., LANCE keyword, many unit abilities, stratagems) cannot be applied. Twin-Linked's re-roll wound ability also can't function without this infrastructure.

### 2.6 HIGH: Stealth Ability — Not Implemented

**Rule:** If every model in a unit has the Stealth ability, ranged attacks targeting that unit subtract 1 from their hit rolls.

**Current state:** No check for the Stealth keyword exists in `RulesEngine.gd`. The `_resolve_assignment_until_wounds()` function checks for Heavy, BGNT, and user-specified modifiers on the attacker's side, but never checks the target unit for defensive abilities like Stealth.

**Impact:** Units with Stealth (e.g., Reivers, Scouts, many Eldar units) receive no defensive benefit. This is a common ability across many armies.

**Fix:** In the hit modifier calculation section of `_resolve_assignment_until_wounds()`, check if all alive models in the target unit have the Stealth keyword, and if so, apply `HitModifier.MINUS_ONE`.

### 2.7 HIGH: Lone Operative — Not Implemented

**Rule:** Unless part of an Attached unit, a unit with Lone Operative can only be selected as the target of a ranged attack if the attacking model is within 12".

**Current state:** No check for Lone Operative exists in `get_eligible_targets()` or `validate_shoot()`. Any unit can be targeted at any range regardless of this ability.

**Impact:** Character models with Lone Operative (e.g., Vindicare Assassin, many standalone characters) can be freely sniped from across the board.

**Fix:** In `get_eligible_targets()`, before adding a target to the eligible list, check if the target has the Lone Operative keyword and is not attached to a bodyguard unit. If so, verify that at least one alive model in the actor unit is within 12" of the target.

### 2.8 ~~HIGH: Battle-shocked Units Cannot Use Pistol in Engagement — Not Enforced~~ FIXED

**Rule:** Battle-shocked units cannot shoot at all (including Pistol weapons while in engagement range). Battle-shock status is checked during the Command Phase.

**Status:** FIXED. Added `battle_shocked` flag check in both `ShootingPhase.gd:_can_unit_shoot()` and `RulesEngine.gd:validate_shoot()`. Battle-shocked units are now completely prevented from shooting.

### 2.9 MEDIUM: Cover Determination Is Simplified — Only Ruins Terrain

**Rule:** Benefit of Cover can be granted by ruins, area terrain, obstacles, and other terrain features. Specific conditions apply depending on terrain type (e.g., "within" for Area Terrain, "behind" for obstacles).

**Current state:** `check_benefit_of_cover()` (`RulesEngine.gd:1440-1461`) only checks for "ruins" terrain type. Other terrain types (woods, craters, barricades, obstacles) are ignored for cover purposes.

**Impact:** Units in non-ruins terrain features receive no cover benefit, even when they should per the rules.

### 2.10 MEDIUM: Devastating Wounds — Mortal Wound Implementation Simplified

**Rule:** Per the updated 10e rules (post-December 2024 FAQ), Devastating Wounds converts critical wounds into mortal wounds equal to the Damage characteristic. These mortal wounds are allocated AFTER all normal attacks are resolved. Mortal wounds spill over to other models.

**Current state:** The implementation applies devastating damage as a pool via `_apply_damage_to_unit_pool()` (`RulesEngine.gd:3777-3790`), which is functionally close. However, it doesn't explicitly model mortal wounds as a distinct damage type — it applies them as regular damage to the unit pool. The spillover behavior (when a model is killed and there's excess damage, it carries to the next model) needs to be verified.

**Impact:** Minor — the functional behavior is mostly correct, but edge cases around mortal wound spillover and interactions with FNP may differ from strict RAW.

### 2.11 MEDIUM: Pistol Restriction — Cannot Fire Other Weapons When Using Pistol

**Rule:** If a model fires a Pistol weapon, it cannot fire any other ranged weapons that turn (even if it's not in engagement range). Conversely, if a model fires a non-Pistol weapon, it cannot fire Pistol weapons.

**Current state:** The code restricts Pistol use to engagement range scenarios correctly. However, there is no enforcement of the mutual exclusivity: a model could theoretically be assigned both a Pistol weapon and a non-Pistol weapon in separate assignments. The validation in `_validate_assign_target()` (`ShootingPhase.gd:180-211`) only checks for weapon-split across targets, not for Pistol/non-Pistol mixing.

**Impact:** A model with both a bolt pistol and a bolter could fire both, which violates the rules. The UI may not make this obvious.

### 2.12 LOW: Unmodified Wound Roll of 1 Always Fails — Not Explicitly Checked

**Rule:** An unmodified wound roll of 1 always fails, regardless of modifiers.

**Current state:** Currently there are no wound modifiers, so this hasn't been an issue. However, when wound modifiers are added, the code at `RulesEngine.gd:718-733` just checks `if roll >= wound_threshold`, which would incorrectly allow a modified 1 to succeed. This needs to be addressed when wound modifiers are implemented.

### 2.13 LOW: Unmodified Save Roll of 1 Always Fails — Checked in Interactive Path Only

**Rule:** An unmodified saving throw of 1 always fails.

**Current state:** The interactive save path in `WoundAllocationOverlay` handles this via the UI. However, the auto-resolve path in `_resolve_assignment()` (`RulesEngine.gd:1129`) does `if save_roll >= save_needed` without explicitly checking for unmodified 1. If the save needed is 1+ (impossible by rules but defensively), this could theoretically pass.

**Impact:** Minimal in practice since saves are always 2+ or worse. But should be enforced defensively.

---

## 3. Multiplayer-Specific Issues

### 3.1 HIGH: Defending Player Has No Agency During Shooting Phase

**Current state:** The shooting phase is entirely driven by the active player. The defending player:
- Cannot use Overwatch
- Cannot use stratagems (Go to Ground, Smokescreen)
- Cannot use reactive abilities
- Can only interact during the wound allocation overlay (which is well-implemented)

**Impact:** The defending player watches passively as their units are shot. In the tabletop game, the defender has several reaction opportunities (Overwatch, Go to Ground for Infantry, Smokescreen for SMOKE keyword units).

### 3.2 MEDIUM: Remote Player Visual Feedback for Shooting Actions — **DONE**

**Resolution:** Implemented in T5-MP3. Added remote player visual feedback for all shooting actions in both NetworkManager.gd and ShootingController.gd:
- ASSIGN_TARGET: Draws orange shooting lines with weapon name labels from shooter to target on the remote player's board
- CLEAR_ASSIGNMENT / CLEAR_ALL_ASSIGNMENTS: Clears shooting line visuals on remote
- CONFIRM_TARGETS: Re-emits `shooting_begun` signal so remote player sees shooting lines and dice log context
- COMPLETE_SHOOTING_FOR_UNIT: Re-emits `shooting_resolved` signal so remote player's visuals are properly cleaned up
- Covers both ENet RPC and WebSocket relay transport modes
- Covers both host→client and client→host directions (host seeing client's actions and vice versa)

### 3.3 MEDIUM: Save Dialog Timing for Defender on Remote Client — **DONE**

**Current state:** The `saves_required` signal triggers the wound allocation overlay. In multiplayer, the save data is broadcast as part of the action result (`save_data_list` in the result payload). The remote client (defender) should receive this and show their own overlay.

**Potential issue:** If the save data broadcast is delayed or lost, the defender may not see the save dialog. The code has defensive logging (`ShootingPhase.gd:601-619`), but there is no explicit retry or confirmation mechanism for the defender acknowledging save results.

- **Resolution:** Implemented save dialog timing reliability (T5-MP4). Added:
  - Defender→attacker acknowledgment: when defender receives and displays the save dialog, sends a `save_dialog_ack` message via relay/RPC
  - Attacker-side "Waiting for defender..." feedback via status label and toast while saves are pending
  - Acknowledgment timeout (8s): if defender doesn't ack, attacker automatically retries the save data broadcast via `save_data_retry` message
  - Processing flag safety timer (10s): resets stuck `processing_saves_signal` flag to prevent permanent lockout
  - State cleanup: `clear_awaiting_saves_state()` called when APPLY_SAVES result arrives
  - Covers both WebSocket relay and ENet RPC transport modes

### 3.4 LOW: Dice Log Not Visible to Remote Player in Real-Time

**Current state:** The `dice_rolled` signal emits dice blocks locally. The remote player receives the dice results through action result broadcasts, but the real-time dice roll animation/display may not be synchronized.

- **Resolution:** Implemented in T5-MP5. The root cause was that `resolution_start` and `weapon_progress` informational dice blocks were emitted locally via signal but not included in broadcast results, so the remote player's dice log missed these context headers. Fixed by:
  - Including `resolution_start` block in the `dice` array returned by `_process_resolve_shooting()` so it's broadcast to remote
  - Including `weapon_progress` block in the `dice` array returned by `_resolve_next_weapon()` for sequential weapon resolution
  - Adding proper `resolution_start` context handler in `ShootingController._on_dice_rolled()` (was previously falling through to generic roll display)
  - Enhanced NetworkManager dice sync logging to show which contexts are being re-emitted
  - Works across both ENet RPC and WebSocket relay transport modes

---

## 4. Code Quality & Architecture Issues

### 4.1 HIGH: Excessive Debug Logging

The `ShootingPhase.gd` file contains **extensive debug logging** with decorative box-drawing characters (`╔═══`, `║`, `╚═══`) throughout the entire file. While useful during development, this creates:
- Performance overhead (string formatting on every action)
- Enormous log output that obscures actual errors
- Code readability issues — the actual logic is buried in print statements

Examples: Lines 389-394, 415-421, 459-471, 508-523, 611-619, 914-936, 982-990, 1421-1425, 1473-1478, 1628-1641, 1705-1727, 1734-1739, 1763-1771, 1813-1821, 1825-1828, 1840-1844, 1857-1869, 1906-1916, 1920-1926 — all contain large print blocks.

**Suggestion:** Gate debug logging behind a debug flag or use `DebugLogger` (which exists as an autoload) consistently instead of raw `print()` calls.

### 4.2 MEDIUM: Duplicate Resolution Paths

Two parallel resolution functions exist:
- `_resolve_assignment()` (`RulesEngine.gd:803-1180`) — resolves hits, wounds, saves, AND damage all at once (auto-resolve)
- `_resolve_assignment_until_wounds()` (`RulesEngine.gd:467-798`) — resolves hits and wounds, then stops for interactive saves

The shooting phase uses `resolve_shoot_until_wounds()` for interactive play, but `_resolve_assignment()` still exists and contains its own save/damage logic that could drift out of sync with the interactive path.

**Risk:** If a keyword or rule is updated in one path but not the other, they'll produce different results. The auto-resolve path doesn't benefit from keyword updates that were only added to the interactive path.

### 4.3 MEDIUM: Single Weapon Result Dialog Missing Hit/Attack Data

In the single-weapon path through `_process_apply_saves()` (`ShootingPhase.gd:1796-1807`), the `last_weapon_result` dictionary has hardcoded zeros:
```
"hits": 0,  # We don't have this data easily accessible in single weapon mode
"total_attacks": 0,  # We don't have this data easily accessible
```

This means the results dialog for single-weapon shooting doesn't show hit count or total attacks, only saves and casualties. The data IS available in the dice log but isn't being extracted.

### 4.4 LOW: Weapon ID Generation Could Collide

`_generate_weapon_id()` creates IDs from weapon names (lowered, spaces to underscores). If two different weapons share the same generated ID (e.g., different variants of "Bolt Rifle"), they'd collide. This hasn't caused visible issues but is a latent risk.

---

## 5. Quality of Life Improvements

### 5.1 HIGH: Auto-Select Weapon for Single-Weapon Units

**Current:** Even if a unit only has one ranged weapon type, the player must manually assign it to each target. This adds unnecessary clicks.

**Suggestion:** If a unit has only one ranged weapon type, auto-assign it when a target is selected. Only show the full weapon assignment UI for units with 2+ weapon types.

### 5.2 HIGH: "Shoot All Remaining" Button

**Current:** After a unit finishes shooting, the player must manually select the next unit. If many units need to shoot, this is tedious.

**Suggestion:** Add a "Shoot All Remaining" or "Auto-Shoot Remaining" option that iterates through all eligible units that haven't shot, using a default target assignment (e.g., nearest eligible target). Include a confirmation step before executing.

### 5.3 HIGH: Show Weapon Stats in Target Assignment UI

**Current:** When assigning weapons to targets, the player must remember weapon profiles (range, S, AP, D) or look them up separately.

**Suggestion:** Show a compact weapon stat line next to each weapon in the assignment panel (e.g., "Bolt Rifle: 24" S4 AP-1 D1 [Rapid Fire 1, Heavy]"). This removes the need to cross-reference unit cards.

### 5.4 MEDIUM: Expected Damage Preview

**Suggestion:** When hovering a weapon over a potential target, show an expected damage preview: "~X hits, ~Y wounds, ~Z unsaved" based on the weapon profile vs target stats. This helps players make informed targeting decisions. The RulesEngine already has all the data needed to compute this.

### 5.5 MEDIUM: Shooting Phase Summary Panel

**Suggestion:** After all units have shot, show a summary panel with total hits/wounds/casualties per target unit, before ending the phase. This gives both players a clear picture of the phase's outcome.

### 5.6 MEDIUM: "Undo Last Assignment" Button

**Current:** The clear button removes all assignments. There's no way to undo just the last one.

**Suggestion:** Add an "Undo Last" button that removes the most recent weapon assignment while keeping previous ones.

### 5.7 LOW: Keyboard Shortcuts for Common Actions

**Suggestion:** Add keyboard shortcuts for frequent actions:
- `Space` or `Enter` to confirm targets
- `Escape` to deselect/cancel
- `Tab` to cycle through eligible units
- `N` to skip current unit
- `E` to end shooting phase

---

## 6. Visual Improvements

### 6.1 HIGH: Show Dice Roll Results with Visual Dice

**Current:** Dice results are shown in a text-based dice log. Both hit and wound rolls appear as numbers in the log.

**Suggestion:** Add animated dice roll visualization — show 3D dice or 2D dice sprites rolling and landing. Highlight critical hits (6s) in gold, misses (1s) in red. This is one of the most impactful visual improvements for engagement, especially in multiplayer where both players watch the rolls.

### 6.2 HIGH: Shooting Line Visual from Attacker to Target

**Current:** An LoS line exists (`los_visual` in `ShootingController.gd:29`) but it appears to be used primarily for LoS debugging. No persistent visual line shows which unit is shooting at which target during resolution.

**Suggestion:** During attack resolution, draw a clear animated line or arrow from the shooting unit to its target. Add a brief muzzle flash or tracer effect. Remove after resolution completes. This gives both players (especially the remote observer) clear visual feedback on what's happening.

### 6.3 MEDIUM: Target Unit Damage Feedback

**Current:** Casualties are applied to models and their sprites are updated. No transition effect exists — models simply disappear or change state.

**Suggestion:** Add a brief damage flash (red tint) when a model takes damage, and a "death" animation (fade out, fall over, or small explosion particle) when destroyed. This gives satisfying visual feedback for successful attacks.

### 6.4 MEDIUM: Range Circle Visualization

**Current:** `ShootingRangeVisual` exists (`ShootingController.gd:133-135`) as a Node2D container. The actual range circle implementation should show the weapon's range as a circle around the selected unit.

**Suggestion:** When a weapon is selected, show its range as a translucent circle on the board. Color-code eligible targets inside the range. Show half-range for Rapid Fire and Melta weapons as a dotted inner circle.

### 6.5 MEDIUM: Wound Allocation Board Highlights

**Current:** `WoundAllocationOverlay` handles wound allocation with board highlighting. This is good.

**Suggestion:** Enhance the overlay with:
- Pulsing highlight on the model that must receive the next wound (priority wounded model)
- Color gradient from green (full health) to red (near death) on model bases
- Small wound counter displayed near each model's sprite

### 6.6 LOW: Weapon Keyword Icons

**Suggestion:** Display small icons next to weapon names in the UI to represent their keywords (e.g., a lightning bolt for LETHAL HITS, a spread for BLAST, a flame for TORRENT). This makes weapon capabilities immediately recognizable without reading text.

### 6.7 LOW: Phase Transition Animation

**Suggestion:** When entering the Shooting Phase, show a brief phase banner ("SHOOTING PHASE" with an appropriate icon) that fades in and out. This clearly signals the phase change to both players.

---

## 7. Summary Table

| Category | Count |
|----------|-------|
| Rules correctly implemented | 35+ |
| Critical missing rules | 2 (Overwatch, 9 weapon keywords) — targeting in engagement FIXED |
| High priority missing rules | 3 (wound modifiers, Stealth, Lone Operative) — Variable dice FIXED, Battle-shock FIXED, IGNORES COVER FIXED |
| Medium priority missing rules | 4 (cover terrain types, DW mortal wound model, Pistol exclusivity, Ignores Cover runtime) |
| Multiplayer issues | 4 (defender agency, visual sync, save timing, dice sync) |
| Code quality issues | 4 (debug logging, duplicate paths, missing data in results, ID collision) |
| QoL improvements | 7 |
| Visual improvements | 7 |

---

## 8. Recommended Priority Order for Fixes

### Tier 1 — Core Rules Compliance (Blocking for Accurate Games)
1. ~~**Targeting units in engagement with friendlies**~~ — FIXED
2. ~~**Variable attacks and damage rolling**~~ — FIXED
3. ~~**ANTI-[KEYWORD] X+**~~ — FIXED
4. **MELTA X** — core weapon type for anti-vehicle
5. **TWIN-LINKED** — common keyword, re-roll wounds
6. ~~**Battle-shocked units cannot shoot**~~ — FIXED
7. ~~**IGNORES COVER**~~ — FIXED

### Tier 2 — Important Defensive Rules
8. **Stealth** — -1 to hit for many units (partially implemented via Smokescreen stratagem, missing as base unit ability)
9. **Lone Operative** — 12" targeting restriction
10. **Wound roll modifiers** — infrastructure needed for many abilities
11. **HAZARDOUS** — affects plasma weapons
12. **INDIRECT FIRE** — key for artillery units
13. **Pistol mutual exclusivity** — prevent firing both Pistol and non-Pistol

### Tier 3 — Polish & Multiplayer
14. ~~**Overwatch / Fire Overwatch stratagem**~~ — DONE (StratagemManager.gd)
15. **PRECISION** — character sniping
16. **Remote player visual feedback** — shooting line, target highlights
17. **Expected damage preview** — QoL
18. ~~**Variable damage rolling**~~ — FIXED (done with variable attacks)
19. **Dice roll visualization** — engagement improvement

### Tier 4 — Nice to Have
20. **LANCE, ONE SHOT, EXTRA ATTACKS** — niche keywords
21. **Go to Ground / Smokescreen stratagems** — needs stratagem system
22. **Phase summary panel** — QoL
23. **Shooting line animations** — visual polish
24. **Keyboard shortcuts** — accessibility

---

## 9. Bug Fixes

### ~~9.1 LoS Debug Visualization Desync (Issue #103)~~ FIXED

**Problem:** The LoS debug button in the HUD was initialized with `button_pressed = true` while the actual `LoSDebugVisual.debug_enabled` defaulted to `false`. This caused:
1. The button to show "ON" when debug was actually OFF, making users think the debugger was active by default
2. Pressing L to "turn off" the debugger actually toggled it ON (opposite of expected)
3. The L key shortcut never synced the button's visual state, causing further desync

**Fix Applied:**
- Changed `Main.gd:739` from `button_pressed = true` to `button_pressed = false` to match the default disabled state
- Added `set_pressed_no_signal()` call in `_toggle_los_debug()` to sync the button state after any toggle (L key or button click)
- `LoSDebugVisual.gd` already had `debug_enabled = false` and comprehensive child node cleanup from a prior fix

**Commit:** `91da311` — "Fix LoS debug button/state desync causing visuals to appear active by default"
**Branch:** `claude/fix-los-debug-tZgYq`
