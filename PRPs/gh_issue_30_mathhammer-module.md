# PRP: Mathhammer Module Implementation

## Issue Information
- **Issue Number**: #30
- **Title**: Mathhammer Module
- **Priority**: Enhancement (Strategic Feature)
- **Confidence Score**: 8/10

## Executive Summary
Implement a comprehensive Monte Carlo simulation system for Warhammer 40k combat calculations. The Mathhammer module will provide statistical analysis of expected damage, kill probability, and outcome distributions for attack scenarios. This implementation leverages the existing mature RulesEngine combat system, adding statistical analysis layers while maintaining compatibility with all current weapon profiles and special rules.

## Current State Analysis

### Existing Foundation Assets
The codebase provides an excellent foundation for Mathhammer implementation:

**RulesEngine.gd (lines 89-143)** - Complete Monte Carlo-ready infrastructure:
- `RNGService` class with seeded dice rolling for reproducible results  
- Full combat sequence: `resolve_shoot()` → hit rolls → wound rolls → save rolls → damage allocation
- Comprehensive weapon parsing from army data including dice notation (`D6`, `D3`, `2D6+1`)
- Weapon profile access: `get_weapon_profile()` and `get_unit_weapons()`
- Target validation and eligibility checking

**UI Architecture (UnitStatsPanel.gd:1-100)** - Proven UI patterns:
- PanelContainer with toggle expansion/collapse functionality
- ScrollContainer for large content with smooth Tween animations
- VBoxContainer layout system for organized content display
- Theme integration and consistent visual design

**Army Data Structure (armies/orks.json:72-83)** - Complete weapon metadata:
```json
{
  "name": "Kombi-weapon", "type": "Ranged", "range": "24",
  "attacks": "1", "ballistic_skill": "5", "strength": "4", 
  "ap": "0", "damage": "1",
  "special_rules": "anti-infantry 4+, devastating wounds, rapid fire 1"
}
```

**Testing Framework** - Established patterns for validation:
- GutTest framework with test board setup (test_shooting_mechanics.gd:8-50)
- Mock unit creation and state validation
- Dice outcome verification and statistical testing

### Integration Points
- **Combat System**: `RulesEngine.resolve_shoot()` provides validated combat resolution
- **UI Framework**: Follow `UnitStatsPanel` patterns for consistent user experience  
- **Data Access**: Use existing `GameState.get_unit()` and army loading systems
- **Phase Integration**: Integrate with shooting/fight phase workflows

## Implementation Design

### Core Architecture

#### 1. Mathhammer Simulation Engine
**File**: `scripts/Mathhammer.gd`

```gdscript
class_name Mathhammer

static func simulate_combat(config: Dictionary) -> Dictionary:
    var trials = config.get("trials", 10000)
    var attackers = config.get("attackers", [])
    var defender = config.get("defender", {})
    var rule_toggles = config.get("rule_toggles", {})
    var phase = config.get("phase", "shooting")
    
    var results = []
    var rng = RulesEngine.RNGService.new(config.get("seed", -1))
    
    for trial in range(trials):
        results.append(_run_trial(attackers, defender, phase, rule_toggles, rng))
    
    return _analyze_results(results, config)
```

**Key Features:**
- **Monte Carlo Engine**: Configurable trial count (default 10,000) for statistical accuracy
- **Rule Toggle System**: Dynamic modifier application (e.g., "Waaagh! active", "Cover", "+1 to hit aura")
- **Multi-Unit Support**: Aggregate attacks from multiple attacking units
- **Phase Flexibility**: Support both shooting and fight phase calculations
- **Reproducible Results**: Seeded RNG for consistent testing and validation

#### 2. User Interface System  
**File**: `scripts/MathhhammerUI.gd`

Following established `UnitStatsPanel` patterns with three main display modes:

**Summary Panel** - Key statistics at a glance:
```
Average Damage: 4.2 wounds
Kill Probability: 67%  
Expected Survivors: 1.3 models
Damage Efficiency: 89% (11% overkill)
```

**Distribution Panel** - Visual probability histogram:
- Custom-drawn histogram using Control nodes and `_draw()` function
- X-axis: Damage amounts (0, 1, 2, 3+)  
- Y-axis: Probability percentages
- Color coding: Green (high probability), Yellow (medium), Red (low)

**Dice Breakdown Panel** - Expandable detailed analysis:
```
Trial 1: 12 attacks → 8 hits → 5 wounds → 2 failed saves → 3 damage
Trial 2: 12 attacks → 6 hits → 4 wounds → 1 failed save → 2 damage
[Aggregate] Avg: 8.2 hits, 5.1 wounds, 2.4 failed saves, 2.7 damage
```

#### 3. Rule Modifier System
**File**: `scripts/MathhhammerRuleModifiers.gd`

**Toggle Panel Implementation:**
```gdscript
# Auto-generated checkboxes for available rules
var available_rules = _extract_unit_rules(attacker_units)
for rule_name in available_rules:
    var checkbox = CheckBox.new()
    checkbox.text = rule_name.capitalize()
    checkbox.toggled.connect(_on_rule_toggled.bind(rule_name))
    rules_container.add_child(checkbox)
```

**Supported Rule Categories:**
- **Hit Modifiers**: Lethal Hits, Sustained Hits, Twin-linked, +1/−1 to hit
- **Wound Modifiers**: Anti-keywords (4+, 3+, 2+), Devastating Wounds, +1/−1 to wound  
- **Save Modifiers**: Ignores Cover, Cover bonus, Invulnerable saves
- **Damage Modifiers**: Feel No Pain, Damage Reduction, Mortal Wounds
- **Situational**: Waaagh! active, Doctrines, Aura effects

#### 4. Results Analysis System
**File**: `scripts/MathhhammerResults.gd`

**Statistical Calculations:**
- **Expected Value**: Probability-weighted average outcomes
- **Distribution Analysis**: Histogram generation from trial results  
- **Confidence Intervals**: Statistical significance of results
- **Efficiency Metrics**: Overkill analysis and optimal target selection

### Implementation Tasks (Priority Order)

#### Phase 1: Core Simulation Engine
1. **Create Mathhammer.gd** with basic Monte Carlo simulation
2. **Integrate with RulesEngine** for combat resolution reuse
3. **Implement configuration system** for attackers/defenders/trials
4. **Add basic result analysis** (mean, distribution, percentiles)

#### Phase 2: Basic UI Integration  
1. **Create MathhhammerUI.gd** following UnitStatsPanel patterns
2. **Implement summary panel** with key statistics display
3. **Add unit selection interface** for attackers and defenders
4. **Integrate with main game UI** as expandable panel

#### Phase 3: Rule Toggle System
1. **Create rule extraction system** from unit weapon data
2. **Implement checkbox-based toggle interface** 
3. **Add rule modifier application** to simulation engine
4. **Validate rule combinations** and conflicting modifiers

#### Phase 4: Advanced Visualization
1. **Custom histogram drawing** using Control node _draw() function
2. **Probability distribution charts** with color coding
3. **Expandable dice breakdown logs** with trial details
4. **Export/sharing capabilities** for analysis results

#### Phase 5: Multi-Unit & Advanced Features
1. **Multi-attacker aggregation** with sequential damage application
2. **Advanced special rules** (Blast, Torrent, Precision, etc.)
3. **Performance optimization** for large-scale simulations
4. **Batch analysis tools** for army-wide effectiveness comparison

## Context References and Examples

### Core Documentation
- **Warhammer 40k Rules**: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/
- **Godot Documentation**: https://docs.godotengine.org/en/4.4/

### External Mathhammer Examples
- **UnitCrunch Calculator**: https://www.unitcrunch.com/ - Reference for multi-unit simulation patterns
- **40K Visual Dice Calculator**: https://40k.ghostlords.com/dice/ - UI design patterns for rule toggles
- **Goonhammer Math Analysis**: https://www.goonhammer.com/hammer-of-math-calculating-expected-values/ - Statistical methodology

### Codebase Integration Patterns
```
40k/
├── autoloads/
│   └── RulesEngine.gd           # REFERENCE: Combat resolution and dice rolling (lines 106-322)
├── scripts/
│   ├── UnitStatsPanel.gd        # REFERENCE: Expandable panel UI patterns (lines 40-100)
│   └── ShootingController.gd    # REFERENCE: Unit selection and target assignment
├── armies/
│   └── orks.json               # REFERENCE: Weapon data structure (lines 72-125)
└── tests/
    └── unit/
        └── test_shooting_mechanics.gd # REFERENCE: Testing patterns (lines 1-50)
```

## Implementation Blueprint

### Core Simulation Logic
```gdscript
# Pseudocode for main simulation engine
func simulate_attack_sequence(attackers, defender, trials=10000, toggles={}):
    var results = []
    
    for trial in range(trials):
        var total_damage = 0
        
        # Process each attacking unit sequentially  
        for attacker in attackers:
            # Leverage existing RulesEngine combat resolution
            var shoot_action = _build_shoot_action(attacker, defender, toggles)
            var result = RulesEngine.resolve_shoot(shoot_action, board_state, rng)
            
            total_damage += _extract_damage_dealt(result)
            
            # Update defender state for subsequent attackers
            _apply_damage_to_board(result.diffs, board_state)
        
        results.append({
            "damage": total_damage,
            "models_killed": _count_models_killed(),
            "overkill": _calculate_overkill(total_damage, defender)
        })
    
    return _analyze_statistical_distribution(results)
```

### UI Integration Approach
```gdscript
# Pseudocode for UI integration
func _ready():
    # Follow UnitStatsPanel expansion pattern
    setup_toggle_button("🎲 Mathhammer Analysis")
    setup_collapsible_container()
    
    # Create three main sections
    summary_panel = create_summary_display()
    distribution_panel = create_histogram_display() 
    breakdown_panel = create_detailed_breakdown()
    
    # Auto-detect available units and weapons
    populate_unit_selectors()
    populate_rule_toggles()
```

### Rule Modifier Integration
```gdscript
# Pseudocode for rule system
func apply_rule_modifiers(base_action, active_toggles):
    var modified_action = base_action.duplicate(true)
    
    # Apply hit roll modifiers
    if active_toggles.get("lethal_hits", false):
        modified_action.hit_auto_wound_on_6 = true
    
    if active_toggles.get("sustained_hits", false):
        modified_action.sustained_hits_value = get_sustained_hits_bonus()
    
    # Apply wound roll modifiers  
    if active_toggles.get("anti_infantry", false):
        modified_action.wound_reroll_on_target_keyword = ["INFANTRY"]
    
    return modified_action
```

## Risk Analysis and Mitigation

### Risk: Performance with Large Simulations
**Issue**: 10,000+ trials with complex rules could impact UI responsiveness
**Mitigation**: 
- Implement background processing with progress callbacks
- Use GDScript threading for heavy calculations  
- Provide trial count configuration (1K/10K/100K options)
- Cache simulation results for repeated configurations

### Risk: Special Rules Complexity
**Issue**: 40k has hundreds of special rules with complex interactions
**Mitigation**:
- Start with core rules (hit/wound/save modifiers) 
- Add special rules incrementally with validation
- Use existing `RulesEngine.validate_weapon_special_rules()` as foundation
- Create rule compatibility matrix for conflicting modifiers

### Risk: UI Responsiveness 
**Issue**: Complex statistical displays could slow down main game interface
**Mitigation**:
- Use lazy loading for histogram generation
- Implement viewport culling for large result datasets
- Follow existing UI patterns for smooth expand/collapse animations
- Defer heavy calculations until panel is expanded

## Validation Gates (Executable)

```bash
# 1. Core Engine Validation
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_mathhammer.gd

# 2. UI Integration Test  
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/ui/test_mathhammer_ui.gd

# 3. Performance Benchmark (should complete <2 seconds for 10K trials)
godot --headless --script="res://tests/performance/benchmark_mathhammer.gd"

# 4. Rule Validation (verify special rules application)
godot --headless --script="res://tests/integration/test_mathhammer_rules.gd"

# 5. Statistical Accuracy (verify Monte Carlo convergence)
godot --headless --script="res://tests/statistical/test_simulation_accuracy.gd"
```

## Success Criteria

1. **Functional**: Monte Carlo simulation runs 10,000 trials in <2 seconds
2. **Accuracy**: Results match analytical calculations within 5% margin of error
3. **Integration**: Seamless UI integration with existing panel architecture  
4. **Extensibility**: Rule toggle system supports 20+ common special rules
5. **Usability**: Intuitive interface for unit selection and configuration
6. **Performance**: No impact on main game performance when panel is collapsed

## Extensibility and Future Enhancements

### Phase 2 Features
- **Batch Analysis**: Compare multiple unit loadouts simultaneously
- **Optimization Suggestions**: Recommend optimal weapon assignments
- **Historical Analysis**: Track simulation results across game sessions
- **Export Capabilities**: CSV/JSON export for external analysis

### Advanced Rule Support
- **Psychic Powers**: Mortal wound generation and denial mechanics
- **Stratagems**: Command Point cost/benefit analysis  
- **Terrain Interaction**: Cover, obscuring, and difficult terrain effects
- **Multi-Phase Analysis**: Combined shooting + fight phase optimization

## Confidence Assessment: 8/10

**High Confidence Factors:**
- Mature existing combat system provides solid foundation (+2)
- Established UI patterns reduce implementation risk (+2)  
- Clear external examples and requirements (+1)
- Comprehensive testing framework available (+1)

**Risk Factors:**
- Special rules complexity may require iterative implementation (-1)
- Performance optimization needs careful tuning (-1)

**Confidence Drivers:**
- **Existing Infrastructure**: RulesEngine provides 80% of required functionality
- **Clear Requirements**: Issue specification aligns perfectly with standard mathhammer tools
- **Proven Patterns**: UI architecture follows established, working codebase conventions
- **Incremental Approach**: Can deliver core functionality first, then add complexity

This PRP provides a comprehensive roadmap for implementing a professional-grade Mathhammer module that leverages existing codebase strengths while delivering the statistical analysis capabilities outlined in the GitHub issue.