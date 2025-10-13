# PRP: Standardize Top Panel UI Across All Game Phases

**GitHub Issue**: #101
**Title**: Update top panel
**Confidence Score**: 8/10

## Problem Statement

The top panel (HUD_Bottom) displays inconsistent button positioning and layout between game phases. Currently:

1. Each phase controller creates its own "End Phase" button with different names and locations
2. UI artifacts from previous phases remain when transitioning to the next phase
3. No consistent cleanup mechanism exists when switching phases
4. Some controllers place buttons in the right panel instead of the bottom HUD

## Current Implementation Issues

### Phase-Specific Button Implementations

Based on codebase analysis at /Users/robertocallaghan/Documents/claude/godotv2/40k:

1. **Deployment Phase** (`Main.gd:56`): Uses `end_deployment_button` from scene file
2. **Command Phase** (`CommandController.gd`): Creates "End Command Phase" button in right panel
3. **Movement Phase** (`MovementController.gd`): Creates "End Movement Phase" button in HUD_Bottom
4. **Shooting Phase** (`ShootingController.gd`): Creates "End Shooting Phase" button in right panel
5. **Charge Phase** (`ChargeController.gd`): Creates "EndChargePhaseButton" in HUD_Bottom
6. **Fight Phase** (`FightController.gd`): Creates "FightPhaseButton" in HUD_Bottom
7. **Scoring Phase** (`ScoringController.gd:107`): Creates "End Turn" button in ScoringControls container
8. **Morale Phase**: Reuses `end_deployment_button` with text "End Morale"

### Key Files to Modify

- `/40k/scripts/Main.gd` - Main UI controller
- `/40k/scenes/Main.tscn` - Main scene with HUD structure
- `/40k/scripts/CommandController.gd` - Command phase controller
- `/40k/scripts/MovementController.gd` - Movement phase controller
- `/40k/scripts/ShootingController.gd` - Shooting phase controller
- `/40k/scripts/ChargeController.gd` - Charge phase controller
- `/40k/scripts/FightController.gd` - Fight phase controller
- `/40k/scripts/ScoringController.gd` - Scoring phase controller
- `/40k/phases/*.gd` - Phase implementations

## Solution Architecture

### Design Principles

Following Godot 4 best practices from https://docs.godotengine.org/en/4.4/tutorials/best_practices/:

1. **Single Source of Truth**: One button location in HUD_Bottom for all phases
2. **Consistent Naming**: Use standardized naming convention for UI elements
3. **Clean State Transitions**: Proper cleanup before setting up new phase UI
4. **Separation of Concerns**: Main.gd manages top panel, controllers manage only their specific UI

### Implementation Blueprint

```gdscript
# Main.gd - Standardized top panel management

# Single button reference for all phases
@onready var phase_action_button: Button = $HUD_Bottom/HBoxContainer/PhaseActionButton

func update_ui_for_phase() -> void:
    # Clear any phase-specific UI artifacts first
    _clear_phase_ui_artifacts()

    # Update labels
    phase_label.text = _get_phase_label_text(current_phase)

    # Configure the single action button for current phase
    phase_action_button.visible = true
    phase_action_button.text = _get_phase_button_text(current_phase)
    phase_action_button.disabled = false

    # Disconnect all previous connections
    if phase_action_button.pressed.is_connected(_on_phase_action_pressed):
        phase_action_button.pressed.disconnect(_on_phase_action_pressed)

    # Connect to appropriate handler
    phase_action_button.pressed.connect(_on_phase_action_pressed)

func _get_phase_button_text(phase: GameStateData.Phase) -> String:
    match phase:
        GameStateData.Phase.DEPLOYMENT: return "End Deployment"
        GameStateData.Phase.COMMAND: return "End Command Phase"
        GameStateData.Phase.MOVEMENT: return "End Movement Phase"
        GameStateData.Phase.SHOOTING: return "End Shooting Phase"
        GameStateData.Phase.CHARGE: return "End Charge Phase"
        GameStateData.Phase.FIGHT: return "End Fight Phase"
        GameStateData.Phase.SCORING: return "End Turn"
        GameStateData.Phase.MORALE: return "End Morale Phase"
        _: return "End Phase"

func _clear_phase_ui_artifacts() -> void:
    # Remove any dynamically added phase-specific buttons
    var hbox = $HUD_Bottom/HBoxContainer
    for child in hbox.get_children():
        if child.name in ["ScoringControls", "MovementButtons", "EndChargePhaseButton", "FightPhaseButton"]:
            child.queue_free()
```

## Implementation Tasks

### Phase 1: Refactor Main.gd Top Panel Management

1. **Update Main.tscn**
   - Rename `EndDeploymentButton` to `PhaseActionButton`
   - Ensure consistent positioning in HBoxContainer

2. **Refactor Main.gd**
   - Create centralized phase button management
   - Implement `_clear_phase_ui_artifacts()` method
   - Update `update_ui_for_phase()` to use single button
   - Add proper signal disconnection before reconnection

### Phase 2: Update Phase Controllers

3. **Remove Controller-Specific Button Creation**
   - Remove button creation code from each controller
   - Remove button references from controller member variables
   - Update controllers to emit signals instead of handling buttons directly

4. **Standardize Controller Cleanup**
   - Ensure each controller's `_exit_tree()` method removes only its UI elements
   - Don't touch HUD_Bottom buttons in controllers

### Phase 3: Testing and Validation

5. **Test Phase Transitions**
   - Verify no UI artifacts remain between phases
   - Ensure button text updates correctly
   - Confirm button functionality works for each phase

## Existing Patterns to Follow

Reference implementation from `Main.gd:_clear_right_panel_phase_ui()`:

```gdscript
func _clear_right_panel_phase_ui() -> void:
    """Completely clear all phase-specific UI from right panel"""
    var container = get_node_or_null("HUD_Right/VBoxContainer")
    if not container:
        print("WARNING: Right panel VBoxContainer not found")
        return

    # List of known phase-specific UI elements to remove
    var phase_ui_patterns = [...]

    # Remove all matching elements
    for pattern in phase_ui_patterns:
        var node = container.get_node_or_null(pattern)
        if node and is_instance_valid(node):
            container.remove_child(node)
            node.queue_free()
```

## Error Handling Strategy

1. **Null Checks**: Always verify node existence before manipulation
2. **Signal Safety**: Check if signal is connected before disconnecting
3. **Graceful Degradation**: If button missing, log warning but don't crash
4. **State Validation**: Verify phase state before UI updates

## Validation Gates

```bash
# Run Godot in headless mode to check for script errors
export PATH="$HOME/bin:$PATH"
timeout 10 godot --headless --quit || echo "Check complete"

# Check for compilation errors
cd 40k && godot --headless --script scripts/Main.gd --check-only

# Run UI tests if they exist
cd 40k && godot --headless --test
```

## Testing Checklist

- [ ] All phases show correct button text
- [ ] Button position remains consistent across phases
- [ ] No duplicate buttons appear
- [ ] Previous phase UI artifacts are removed
- [ ] Button functionality works correctly for each phase
- [ ] Phase transitions are smooth without flicker
- [ ] Signal connections don't accumulate over time

## References

- Godot 4 UI Best Practices: https://docs.godotengine.org/en/4.4/tutorials/best_practices/
- State Design Pattern: https://docs.godotengine.org/en/3.2/tutorials/misc/state_design_pattern.html
- Scene Organization: https://docs.godotengine.org/en/4.4/tutorials/best_practices/scene_organization.html

## Additional Context

The game implements a Warhammer 40K tabletop game with multiple phases. The top panel (HUD_Bottom) serves as the primary control interface for phase progression. Maintaining consistency here is crucial for user experience as players spend significant time interacting with these controls throughout gameplay.

Current scene structure (Main.tscn):
- HUD_Bottom/HBoxContainer contains: PhaseLabel, ActivePlayerBadge, StatusLabel, EndDeploymentButton
- Controllers should only modify HUD_Right and their specific UI areas
- HUD_Bottom should be exclusively managed by Main.gd

## Success Criteria

1. Single, consistently positioned button for all phase actions
2. No UI artifacts between phase transitions
3. Existing functionality preserved without regression
4. Code follows established patterns in the codebase
5. Clear separation between Main.gd (top panel) and controller responsibilities

---

**Confidence Score Rationale**: 8/10
- Clear problem identification with specific code locations
- Well-defined solution architecture
- Existing patterns to follow
- Manageable scope with clear boundaries
- -2 points for potential edge cases in phase transitions and signal management complexity