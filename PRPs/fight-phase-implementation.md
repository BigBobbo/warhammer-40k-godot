# Fight Phase Implementation PRP

## Overview

Implement a complete **Fight Phase** for the Warhammer 40k Godot game following 10e core rules. This phase allows units in engagement range to resolve close combat through a structured sequence of pile in, attack resolution, and consolidation. Implementation will use full dice mechanics mirroring the Shooting Phase patterns for consistency.

**Score: 9/10** - Comprehensive context with full dice mechanics and established patterns for one-pass implementation success.

## Context & Documentation

### Core Documentation
- **Warhammer 40k 10e Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#FIGHT-PHASE
- **Godot 4.4 Documentation**: https://docs.godotengine.org/en/4.4/
- **Current Stub**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/FightPhase.gd`

### Key Rule References
From 10e Core Rules:
- Fight sequence: **Fights First** → **Remaining Combats** 
- Players **alternate** selecting units within each priority tier
- Each activation: **Pile In (3")** → **Make Attacks** → **Consolidate (3")**
- Only models within **Engagement Range (1" horiz/5" vert)** can fight
- Movement must be toward **closest enemy model**
- Attack sequence: **Hit** → **Wound** → **Allocate** → **Save** → **Damage**
- Units that **charged this turn** have Fights First priority

## Existing Codebase Patterns to Reuse

### Phase Structure Pattern (from ShootingPhase.gd)
```gdscript
# ShootingPhase.gd:7-11 - Signals for UI communication
signal unit_selected_for_fighting(unit_id: String)
signal targets_available(unit_id: String, eligible_targets: Dictionary)
signal fighting_begun(unit_id: String)
signal fighting_resolved(unit_id: String, target_unit_id: String, result: Dictionary)
signal dice_rolled(dice_data: Dictionary)

# ShootingPhase.gd:13-19 - State tracking
var active_fighter_id: String = ""
var pending_attacks: Array = []  # Attack assignments before confirmation
var confirmed_attacks: Array = []  # Attacks ready to resolve
var resolution_state: Dictionary = {}
var dice_log: Array = []
var units_that_fought: Array = []
```

### Dice Resolution Pattern (from RulesEngine.gd)
```gdscript
# RulesEngine.gd:1420-1530 - Full attack resolution with dice
static func resolve_melee_attacks(action: Dictionary, board: Dictionary, rng: RNGService) -> Dictionary:
    # Reuse exact pattern from resolve_shoot but with WS instead of BS
    var assignments = action.payload.assignments
    for assignment in assignments:
        var hits = _roll_to_hit_melee(weapon_skill, rolls_needed, rng)
        var wounds = _roll_to_wound(weapon_strength, target_toughness, hits, rng)
        var saves = _roll_saves(wounds, armor_save, ap, rng)
        var damage = _apply_damage(failed_saves, weapon_damage, rng)
```

### Movement Validation Pattern (from MovementPhase.gd)
```gdscript
# MovementPhase.gd:672-750 - Coherency and engagement validation
func _validate_unit_coherency(unit_id: String, new_positions: Dictionary) -> Dictionary
func _check_engagement_range_constraints(unit_id: String, positions: Dictionary) -> bool
```

### UI Controller Pattern (from ShootingController.gd)
```gdscript
# ShootingController.gd:40-76 - UI setup and references
func _setup_ui_references() -> void
func _create_fight_visuals() -> void
func _setup_bottom_hud() -> void
func _setup_right_panel() -> void
```

## Implementation Blueprint

### 1. Core Fight Phase Structure

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/phases/FightPhase.gd`

Replace existing stub with full implementation:

```gdscript
extends BasePhase
class_name FightPhase

# Signals (mirror ShootingPhase pattern)
signal unit_selected_for_fighting(unit_id: String)
signal pile_in_preview(unit_id: String, movements: Dictionary)
signal attacks_resolved(unit_id: String, target_id: String, result: Dictionary)
signal consolidate_preview(unit_id: String, movements: Dictionary)
signal dice_rolled(dice_data: Dictionary)
signal fight_order_determined(fight_sequence: Array)

# Fight state tracking
var active_fighter_id: String = ""
var fight_sequence: Array = []  # Ordered list of units to fight
var current_fight_index: int = 0
var pending_attacks: Array = []
var confirmed_attacks: Array = []
var resolution_state: Dictionary = {}
var dice_log: Array = []
var units_that_fought: Array = []

# Fight priority tiers
enum FightPriority {
    FIGHTS_FIRST = 0,  # Charged units + abilities
    NORMAL = 1,
    FIGHTS_LAST = 2
}

func _on_phase_enter() -> void:
    log_phase_message("Entering Fight Phase")
    _initialize_fight_sequence()
    _check_for_combats()

func _initialize_fight_sequence() -> void:
    # Build fight order: Fights First -> Normal -> Fights Last
    var fights_first = []
    var normal = []
    var fights_last = []
    
    for unit_id in all_units:
        if _is_unit_in_combat(unit):
            var priority = _get_fight_priority(unit)
            match priority:
                FightPriority.FIGHTS_FIRST:
                    fights_first.append(unit_id)
                FightPriority.NORMAL:
                    normal.append(unit_id)
                FightPriority.FIGHTS_LAST:
                    fights_last.append(unit_id)
    
    # Build alternating sequence for each tier
    fight_sequence = _build_alternating_sequence(fights_first)
    fight_sequence.append_array(_build_alternating_sequence(normal))
    fight_sequence.append_array(_build_alternating_sequence(fights_last))
    
    emit_signal("fight_order_determined", fight_sequence)
```

### 2. Action Types Implementation

#### `SELECT_FIGHTER`
```gdscript
func _validate_select_fighter(action: Dictionary) -> Dictionary:
    var unit_id = action.get("unit_id", "")
    
    # Check it's this unit's turn in sequence
    if fight_sequence[current_fight_index] != unit_id:
        return {"valid": false, "errors": ["Not this unit's turn to fight"]}
    
    # Check unit hasn't already fought
    if unit_id in units_that_fought:
        return {"valid": false, "errors": ["Unit has already fought"]}
    
    # Check unit is in engagement range
    if not _is_unit_in_combat(get_unit(unit_id)):
        return {"valid": false, "errors": ["Unit not in engagement range"]}
    
    return {"valid": true}

func _process_select_fighter(action: Dictionary) -> Dictionary:
    active_fighter_id = action.unit_id
    
    # Get eligible targets (enemy units within engagement)
    var targets = _get_eligible_melee_targets(active_fighter_id)
    emit_signal("unit_selected_for_fighting", active_fighter_id)
    emit_signal("targets_available", active_fighter_id, targets)
    
    return create_result(true, [])
```

#### `PILE_IN`
```gdscript
func _validate_pile_in(action: Dictionary) -> Dictionary:
    var unit_id = action.get("unit_id", "")
    var movements = action.get("movements", {})  # model_id -> new_position
    
    # Validate each model moves max 3" toward closest enemy
    for model_id in movements:
        var old_pos = _get_model_position(unit_id, model_id)
        var new_pos = movements[model_id]
        
        # Check 3" limit
        var distance = Measurement.distance_inches(old_pos, new_pos)
        if distance > 3.0:
            return {"valid": false, "errors": ["Pile in exceeds 3\" limit"]}
        
        # Check movement is toward closest enemy
        if not _is_moving_toward_closest_enemy(unit_id, model_id, old_pos, new_pos):
            return {"valid": false, "errors": ["Must pile in toward closest enemy"]}
    
    # Check unit coherency maintained
    if not _validate_unit_coherency(unit_id, movements).valid:
        return {"valid": false, "errors": ["Breaks unit coherency"]}
    
    return {"valid": true}

func _process_pile_in(action: Dictionary) -> Dictionary:
    var changes = []
    var movements = action.movements
    
    for model_id in movements:
        changes.append({
            "op": "set",
            "path": "units.%s.models.%s.position" % [action.unit_id, model_id],
            "value": movements[model_id]
        })
    
    emit_signal("pile_in_preview", action.unit_id, movements)
    return create_result(true, changes)
```

#### `ASSIGN_ATTACKS`
```gdscript
func _process_assign_attacks(action: Dictionary) -> Dictionary:
    # Mirror ShootingPhase weapon assignment pattern
    var unit_id = action.get("unit_id", "")
    var target_id = action.get("target_id", "")
    var weapon_id = action.get("weapon_id", "")
    
    pending_attacks.append({
        "attacker": unit_id,
        "target": target_id,
        "weapon": weapon_id,
        "models": action.get("attacking_models", [])
    })
    
    log_phase_message("Assigned %s attacks to %s" % [weapon_id, target_id])
    return create_result(true, [])
```

#### `CONFIRM_AND_RESOLVE_ATTACKS`
```gdscript
func _process_confirm_and_resolve_attacks(action: Dictionary) -> Dictionary:
    confirmed_attacks = pending_attacks.duplicate(true)
    pending_attacks.clear()
    
    emit_signal("fighting_begun", active_fighter_id)
    
    # AUTO-RESOLVE like ShootingPhase
    var melee_action = {
        "type": "FIGHT",
        "actor_unit_id": active_fighter_id,
        "payload": {
            "assignments": confirmed_attacks
        }
    }
    
    var rng_service = RulesEngine.RNGService.new()
    var result = RulesEngine.resolve_melee_attacks(melee_action, game_state_snapshot, rng_service)
    
    # Process casualties and state changes
    if result.success:
        _apply_combat_results(result)
        emit_signal("attacks_resolved", active_fighter_id, confirmed_attacks[0].target, result)
        emit_signal("dice_rolled", result.get("dice", {}))
    
    return result
```

#### `CONSOLIDATE`
```gdscript
func _validate_consolidate(action: Dictionary) -> Dictionary:
    # Identical to pile in but happens after fighting
    var unit_id = action.get("unit_id", "")
    
    if not unit_id in units_that_fought:
        return {"valid": false, "errors": ["Unit must fight before consolidating"]}
    
    # Same 3" toward closest enemy validation as pile in
    return _validate_pile_in(action)

func _process_consolidate(action: Dictionary) -> Dictionary:
    var result = _process_pile_in(action)  # Reuse pile in logic
    
    # Mark unit as complete
    units_that_fought.append(action.unit_id)
    current_fight_index += 1
    
    # Check if more units to fight
    if current_fight_index < fight_sequence.size():
        var next_unit = fight_sequence[current_fight_index]
        log_phase_message("Next to fight: %s" % next_unit)
    else:
        emit_signal("phase_completed")
    
    return result
```

### 3. FightController Implementation

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/scripts/FightController.gd` (NEW)

```gdscript
extends Node2D
class_name FightController

# Mirrors ShootingController structure
signal fight_action_requested(action: Dictionary)
signal movement_preview_updated(unit_id: String, valid: bool)

# Fight state
var current_phase = null  # FightPhase reference
var active_fighter_id: String = ""
var eligible_targets: Dictionary = {}
var selected_target_id: String = ""
var attack_assignments: Dictionary = {}

# UI References (reuse ShootingController patterns)
var board_view: Node2D
var pile_in_arrows: Node2D  # Show 3" movement arrows
var consolidate_arrows: Node2D
var engagement_indicators: Node2D
var hud_bottom: Control
var hud_right: Control

# UI Elements
var fight_order_list: ItemList  # Shows fight sequence
var unit_selector: ItemList
var weapon_selector: Tree
var target_selector: ItemList
var pile_in_button: Button
var fight_button: Button
var consolidate_button: Button
var dice_log_display: RichTextLabel

func _ready() -> void:
    _setup_ui_references()
    _create_combat_visuals()
    _connect_phase_signals()

func _setup_bottom_hud() -> void:
    # Create fight-specific controls
    var fight_controls = HBoxContainer.new()
    fight_controls.name = "FightControls"
    
    # Fight sequence display
    var sequence_label = Label.new()
    sequence_label.text = "Fight Order:"
    fight_controls.add_child(sequence_label)
    
    fight_order_list = ItemList.new()
    fight_order_list.custom_minimum_size = Vector2(200, 60)
    fight_controls.add_child(fight_order_list)
    
    # Action buttons
    pile_in_button = Button.new()
    pile_in_button.text = "Pile In (3\")"
    pile_in_button.pressed.connect(_on_pile_in_pressed)
    fight_controls.add_child(pile_in_button)
    
    fight_button = Button.new()
    fight_button.text = "Fight!"
    fight_button.pressed.connect(_on_fight_pressed)
    fight_controls.add_child(fight_button)
    
    consolidate_button = Button.new()
    consolidate_button.text = "Consolidate (3\")"
    consolidate_button.pressed.connect(_on_consolidate_pressed)
    fight_controls.add_child(consolidate_button)
    
    hud_bottom.add_child(fight_controls)
```

### 4. RulesEngine Extensions

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/autoloads/RulesEngine.gd`

Add melee combat resolution functions:

```gdscript
# Reuse shooting mechanics with melee stats
static func resolve_melee_attacks(action: Dictionary, board: Dictionary, rng: RNGService) -> Dictionary:
    var result = {"success": true, "diffs": [], "dice": [], "log_text": ""}
    var assignments = action.get("payload", {}).get("assignments", [])
    
    for assignment in assignments:
        var attacker_id = assignment.get("attacker", "")
        var target_id = assignment.get("target", "")
        var weapon_id = assignment.get("weapon", "")
        
        # Get weapon profile (melee weapons in same format as ranged)
        var weapon = get_weapon_profile(weapon_id)
        var attacks = weapon.get("attacks", 1)
        
        # Get unit stats
        var attacker = board.units[attacker_id]
        var target = board.units[target_id]
        var weapon_skill = attacker.meta.stats.get("weapon_skill", 4)
        var strength = weapon.get("strength", attacker.meta.stats.get("strength", 3))
        var toughness = target.meta.stats.get("toughness", 4)
        var ap = weapon.get("ap", 0)
        var damage = weapon.get("damage", 1)
        
        # Roll to hit (WS instead of BS)
        var hit_rolls = rng.roll_d6(attacks)
        var hits = 0
        for roll in hit_rolls:
            if roll >= weapon_skill:
                hits += 1
            result.dice.append({
                "context": "hit_roll_melee",
                "roll": roll,
                "target": weapon_skill,
                "success": roll >= weapon_skill
            })
        
        # Roll to wound (same as shooting)
        var wound_target = _get_wound_target(strength, toughness)
        var wound_rolls = rng.roll_d6(hits)
        var wounds = 0
        for roll in wound_rolls:
            if roll >= wound_target:
                wounds += 1
            result.dice.append({
                "context": "wound_roll",
                "roll": roll,
                "target": wound_target,
                "success": roll >= wound_target
            })
        
        # Saves and damage (same as shooting)
        var save_results = _process_saves(wounds, target, ap, rng)
        result.dice.append_array(save_results.dice)
        
        # Apply damage to models
        var damage_results = _apply_damage_to_unit(target_id, save_results.failed_saves, damage, board, rng)
        result.diffs.append_array(damage_results.diffs)
        
        # Log results
        result.log_text += "Melee: %d attacks, %d hits, %d wounds, %d damage\n" % [attacks, hits, wounds, damage_results.casualties]
    
    return result

static func get_fight_priority(unit: Dictionary) -> int:
    # Check if unit charged this turn
    if unit.get("flags", {}).get("charged_this_turn", false):
        return 0  # FIGHTS_FIRST
    
    # Check for Fights First ability
    var abilities = unit.get("meta", {}).get("abilities", [])
    if "fights_first" in abilities:
        return 0
    
    # Check for Fights Last debuff
    if "fights_last" in abilities or unit.get("status_effects", {}).get("fights_last", false):
        return 2  # FIGHTS_LAST
    
    return 1  # NORMAL

static func is_in_engagement_range(model1_pos: Vector2, model2_pos: Vector2, base1_mm: float, base2_mm: float) -> bool:
    var distance = Measurement.distance_inches(model1_pos, model2_pos)
    var base_distance = Measurement.mm_to_inches(base1_mm + base2_mm) / 2.0
    return distance - base_distance <= 1.0  # 1" engagement range
```

### 5. Integration with Existing Systems

#### Connect to Charge Phase
```gdscript
# ChargePhase.gd - Set flag for successful charges
changes.append({
    "op": "set",
    "path": "units.%s.flags.charged_this_turn" % unit_id,
    "value": true
})
```

#### Add Melee Weapons to Army Data
```json
// In space_marines.json
"weapons": {
    "Chainsword": {
        "type": "melee",
        "attacks": 3,
        "weapon_skill": 3,  // Or use unit's WS
        "strength": 4,
        "ap": -1,
        "damage": 1
    },
    "Power Fist": {
        "type": "melee",
        "attacks": 2,
        "weapon_skill": 3,
        "strength": 8,
        "ap": -2,
        "damage": 2
    }
}
```

### 6. Testing Suite

**File**: `/Users/robertocallaghan/Documents/claude/godotv2/40k/tests/phases/test_fight_phase_full.gd` (NEW)

```gdscript
extends BasePhaseTest

func test_fight_sequence_ordering():
    # Setup units with different priorities
    var charged_unit = create_test_unit({"charged_this_turn": true})
    var normal_unit = create_test_unit({})
    var fights_last_unit = create_test_unit({"fights_last": true})
    
    fight_phase.enter_phase(test_state)
    
    # Verify sequence order
    assert_eq(fight_phase.fight_sequence[0], charged_unit.id)
    assert_eq(fight_phase.fight_sequence[1], normal_unit.id) 
    assert_eq(fight_phase.fight_sequence[2], fights_last_unit.id)

func test_pile_in_validation():
    # Test 3" movement limit
    var pile_in_action = {
        "type": "PILE_IN",
        "unit_id": "test_unit",
        "movements": {
            "model_1": Vector2(100, 100)  # From 0,0 = too far
        }
    }
    
    var result = fight_phase.validate_action(pile_in_action)
    assert_false(result.valid, "Pile in beyond 3\" should fail")

func test_full_combat_resolution():
    # Test complete fight sequence with dice
    var select_action = {"type": "SELECT_FIGHTER", "unit_id": "unit_1"}
    var assign_action = {
        "type": "ASSIGN_ATTACKS",
        "unit_id": "unit_1",
        "target_id": "enemy_1",
        "weapon_id": "Chainsword"
    }
    var resolve_action = {"type": "CONFIRM_AND_RESOLVE_ATTACKS"}
    
    # Execute sequence
    fight_phase.execute_action(select_action)
    fight_phase.execute_action(assign_action)
    var result = fight_phase.execute_action(resolve_action)
    
    # Verify dice were rolled
    assert_true(result.has("dice"))
    assert_true(result.dice.size() > 0)
    
    # Verify damage applied
    var enemy = fight_phase.get_unit("enemy_1")
    assert_lt(enemy.models[0].current_wounds, enemy.models[0].max_wounds)

func test_alternating_activation():
    # Test player alternation in same priority tier
    var p1_units = ["p1_unit_1", "p1_unit_2"]
    var p2_units = ["p2_unit_1", "p2_unit_2"]
    
    fight_phase._build_alternating_sequence(p1_units + p2_units)
    
    # Should alternate: p1, p2, p1, p2
    assert_eq(fight_phase.fight_sequence[0], "p1_unit_1")
    assert_eq(fight_phase.fight_sequence[1], "p2_unit_1")
    assert_eq(fight_phase.fight_sequence[2], "p1_unit_2")
    assert_eq(fight_phase.fight_sequence[3], "p2_unit_2")
```

## Implementation Tasks

### Phase 1: Core Infrastructure (Day 1)
1. **Replace FightPhase.gd stub** - Full BasePhase implementation with fight sequence
2. **Add fight priority system** - Fights First/Normal/Fights Last categorization
3. **Implement alternating activation** - Player alternation within priority tiers
4. **Create engagement range checking** - Determine which units can fight
5. **Add phase signals** - UI communication for fight order and selection

### Phase 2: Movement Mechanics (Day 1-2)
6. **Implement PILE_IN validation** - 3" movement toward closest enemy
7. **Add movement visualization** - Arrow indicators for pile in direction
8. **Implement CONSOLIDATE** - Post-combat 3" movement
9. **Add coherency validation** - Ensure unit stays together
10. **Create closest enemy calculation** - For movement direction validation

### Phase 3: Combat Resolution (Day 2)
11. **Add SELECT_FIGHTER action** - Choose unit from fight sequence
12. **Implement ASSIGN_ATTACKS** - Weapon and target selection
13. **Create CONFIRM_AND_RESOLVE_ATTACKS** - Full dice resolution
14. **Add melee hit rolls** - Using Weapon Skill instead of Ballistic Skill
15. **Implement wound/save/damage** - Reuse shooting mechanics

### Phase 4: RulesEngine Integration (Day 2-3)
16. **Add resolve_melee_attacks()** - Mirror resolve_shoot with WS
17. **Create get_fight_priority()** - Determine unit fight order
18. **Add is_in_engagement_range()** - Check combat eligibility
19. **Implement melee weapon profiles** - Add to army JSON files
20. **Add charge flag tracking** - From Charge Phase integration

### Phase 5: UI Controller (Day 3)
21. **Create FightController.gd** - New UI controller
22. **Add fight sequence display** - Show order of activation
23. **Implement pile in interface** - 3" movement controls
24. **Add attack assignment UI** - Weapon/target selection
25. **Create dice log display** - Show combat results

### Phase 6: Testing & Polish (Day 3-4)
26. **Write comprehensive unit tests** - All action types and validation
27. **Add integration tests** - Full fight sequence flow
28. **Test alternating activation** - Proper player switching
29. **Verify dice mechanics** - Accurate probability calculations
30. **Polish visual feedback** - Movement arrows, combat indicators

## Validation Gates

### Automated Testing
```bash
# Run fight phase tests
godot --headless --script addons/gut/gut_cmdln.gd -gtest=test_fight_phase_full -gexit

# Integration with other phases
godot --headless --script addons/gut/gut_cmdln.gd -gtest=test_phase_transitions -gexit

# Full combat flow
godot --headless --script addons/gut/gut_cmdln.gd -gtest=test_charge_to_fight_flow -gexit
```

### Manual Validation Checklist
1. ✅ Units that charged fight first
2. ✅ Players alternate unit selection
3. ✅ Pile in moves 3" toward closest enemy
4. ✅ Only engaged models can attack
5. ✅ Dice rolls use Weapon Skill
6. ✅ Damage removes models correctly
7. ✅ Consolidate moves 3" after fighting
8. ✅ Phase completes when all units fought
9. ✅ UI shows fight order clearly
10. ✅ Movement previews show legal moves

## Critical Implementation Notes

### Reusing Shooting Patterns
- **Action flow**: SELECT → ASSIGN → CONFIRM → AUTO-RESOLVE
- **Dice mechanics**: Same roll_to_hit/wound/save functions, just WS instead of BS
- **State tracking**: Same patterns for active unit, pending/confirmed assignments
- **Signal emission**: Same UI update patterns for dice results and casualties

### Key Differences from Shooting
- **Alternating activation** instead of one player resolving all
- **Movement phases** (pile in/consolidate) within activation
- **Engagement range** constraint instead of weapon range
- **Fight priority** system for sequencing

### Integration Points
- **From Charge Phase**: Read `charged_this_turn` flag for Fights First
- **To Morale Phase**: Casualties may trigger morale checks
- **With GameState**: Update unit positions and model casualties
- **With UI**: Show fight order, movement previews, dice results

## Success Metrics

- All existing tests continue to pass
- New fight phase tests achieve 100% pass rate
- Manual gameplay shows correct 10e fight sequence
- Dice probability matches expected WS/S/T calculations
- UI clearly shows fight order and current activation
- Movement validation prevents illegal pile in/consolidate
- Performance acceptable with 20+ models in combat

## Confidence Score: 9/10

High confidence due to:
- Extensive reuse of proven shooting phase patterns
- Clear 10e rules for fight sequencing
- Existing movement validation from Movement Phase
- Comprehensive test coverage planned
- Well-established dice mechanics from RulesEngine

This PRP provides complete implementation guidance for a production-ready Fight Phase that integrates seamlessly with existing systems while adding the unique mechanics of close combat resolution.