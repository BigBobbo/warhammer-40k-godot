# PRP: Standardize Right Panel UI Across All Game Phases

**GitHub Issue**: #102
**Title**: Right hand panel update
**Confidence Score**: 8/10

## Problem Statement

The right panel (HUD_Right) displays inconsistent button positioning, layout, and naming conventions between game phases. Currently:

1. Each phase controller creates its own panel structure with different naming patterns
2. UI artifacts from previous phases remain when transitioning to the next phase
3. Inconsistent use of ScrollContainer across phases
4. No consistent cleanup mechanism exists when switching phases
5. Each controller manages its own right panel structure independently

## Current Implementation Issues

### Phase-Specific Panel Implementations

Based on codebase analysis at /Users/robertocallaghan/Documents/claude/godotv2/40k:

1. **Movement Phase** (`MovementController.gd:236-255`):
   - Uses custom section names: `Section1_UnitList`, `Section2_UnitDetails`, `Section3_ModeSelection`, `Section4_Actions`
   - Creates sections directly in VBoxContainer
   - No ScrollContainer wrapper
   - Custom cleanup in `_exit_tree()`

2. **Shooting Phase** (`ShootingController.gd:129-228`):
   - Uses `ShootingScrollContainer` > `ShootingPanel` structure
   - Consistent use of ScrollContainer
   - Custom minimum size: `Vector2(250, 400)`
   - Clean structure but unique naming

3. **Charge Phase** (`ChargeController.gd:89-92`):
   - Cleans up: `ChargePanel`, `ChargeScrollContainer`, `ChargeActions`
   - Implies similar structure to shooting phase
   - Custom cleanup patterns

4. **Fight Phase** (`FightController.gd:84-87`):
   - Cleans up: `FightPanel`, `FightScrollContainer`, `FightSequence`, `FightActions`
   - Most complex cleanup list
   - Multiple UI elements to manage

5. **Command Phase** (`CommandController.gd:31-34`):
   - Uses `CommandPanel`, `CommandScrollContainer`
   - Minimal UI elements
   - Simple structure

6. **Scoring Phase** (`ScoringController.gd:32-35`):
   - Uses `ScoringPanel`, `ScoringScrollContainer`
   - Simple structure
   - Consistent with command phase pattern

### Key Files to Modify

- `/40k/scripts/Main.gd` - Main UI controller with `_clear_right_panel_phase_ui()` method
- `/40k/scripts/MovementController.gd` - Movement phase controller
- `/40k/scripts/ShootingController.gd` - Shooting phase controller
- `/40k/scripts/ChargeController.gd` - Charge phase controller
- `/40k/scripts/FightController.gd` - Fight phase controller
- `/40k/scripts/CommandController.gd` - Command phase controller
- `/40k/scripts/ScoringController.gd` - Scoring phase controller
- `/40k/scripts/DeploymentController.gd` - Deployment phase controller (if applicable)

## Solution Architecture

### Design Principles

Following Godot 4 best practices from https://docs.godotengine.org/en/4.4/tutorials/best_practices/:

1. **Consistent Structure**: All phases use same container hierarchy
2. **Standardized Naming**: Phase-specific names follow `[Phase]Panel` pattern
3. **Clean State Transitions**: Proper cleanup before setting up new phase UI
4. **Separation of Concerns**: Main.gd manages container, controllers manage only their specific content

### Standardized Right Panel Structure

```
HUD_Right/VBoxContainer/
├── UnitListPanel (persistent, show/hide based on phase needs)
├── UnitCard (persistent, show/hide based on phase needs)
└── [Phase]ScrollContainer (created by controller)
    └── [Phase]Panel (created by controller)
        └── [Phase-specific UI elements]
```

### Naming Convention Standard

**Container Naming Pattern:**
- Scroll Container: `[Phase]ScrollContainer` (e.g., `MovementScrollContainer`, `ShootingScrollContainer`)
- Main Panel: `[Phase]Panel` (e.g., `MovementPanel`, `ShootingPanel`)
- Action Container: `[Phase]Actions` (if needed) (e.g., `MovementActions`, `ShootingActions`)

**Phase Name Mapping:**
- Deployment → `DeploymentScrollContainer`, `DeploymentPanel`
- Command → `CommandScrollContainer`, `CommandPanel`
- Movement → `MovementScrollContainer`, `MovementPanel`
- Shooting → `ShootingScrollContainer`, `ShootingPanel`
- Charge → `ChargeScrollContainer`, `ChargePanel`
- Fight → `FightScrollContainer`, `FightPanel`
- Scoring → `ScoringScrollContainer`, `ScoringPanel`
- Morale → `MoraleScrollContainer`, `MoralePanel`

### Implementation Blueprint

```gdscript
# Base pattern for all phase controllers

func _setup_right_panel() -> void:
    var container = hud_right.get_node_or_null("VBoxContainer")
    if not container:
        push_error("HUD_Right/VBoxContainer not found")
        return

    # Hide persistent UI elements if not needed
    var unit_list = container.get_node_or_null("UnitListPanel")
    if unit_list:
        unit_list.visible = false  # or true, based on phase needs

    var unit_card = container.get_node_or_null("UnitCard")
    if unit_card:
        unit_card.visible = false  # or true, based on phase needs

    # Create scroll container with standard naming
    var scroll_container = ScrollContainer.new()
    scroll_container.name = "[Phase]ScrollContainer"  # e.g., MovementScrollContainer
    scroll_container.custom_minimum_size = Vector2(250, 400)
    scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
    container.add_child(scroll_container)

    # Create main panel with standard naming
    var phase_panel = VBoxContainer.new()
    phase_panel.name = "[Phase]Panel"  # e.g., MovementPanel
    phase_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll_container.add_child(phase_panel)

    # Add phase-specific UI elements to phase_panel
    _create_phase_ui(phase_panel)

func _create_phase_ui(parent: VBoxContainer) -> void:
    # Phase-specific implementation
    pass
```

### Main.gd Cleanup Enhancement

```gdscript
# Main.gd - Enhanced cleanup method

func _clear_right_panel_phase_ui() -> void:
    """Completely clear all phase-specific UI from right panel"""
    var container = get_node_or_null("HUD_Right/VBoxContainer")
    if not container:
        print("WARNING: Right panel VBoxContainer not found")
        return

    # Updated list with standardized names
    var phase_ui_patterns = [
        # Standardized scroll containers
        "DeploymentScrollContainer", "CommandScrollContainer",
        "MovementScrollContainer", "ShootingScrollContainer",
        "ChargeScrollContainer", "FightScrollContainer",
        "ScoringScrollContainer", "MoraleScrollContainer",

        # Standardized panels
        "DeploymentPanel", "CommandPanel",
        "MovementPanel", "ShootingPanel",
        "ChargePanel", "FightPanel",
        "ScoringPanel", "MoralePanel",

        # Legacy names (for transition period)
        "Section1_UnitList", "Section2_UnitDetails",
        "Section3_ModeSelection", "Section4_Actions",
        "MovementActions",
        "ShootingControls", "WeaponTree", "TargetBasket",
        "ChargeActions", "ChargeStatus",
        "FightSequence", "FightActions",

        # Generic phase elements
        "PhasePanel", "PhaseControls", "PhaseActions"
    ]

    # Remove all matching elements
    for pattern in phase_ui_patterns:
        var node = container.get_node_or_null(pattern)
        if node and is_instance_valid(node):
            print("Main: Removing phase UI element: ", pattern)
            container.remove_child(node)
            node.queue_free()

    # Reset visibility of persistent elements
    var unit_list = container.get_node_or_null("UnitListPanel")
    if unit_list:
        unit_list.visible = true  # Default visible

    var unit_card = container.get_node_or_null("UnitCard")
    if unit_card:
        unit_card.visible = false  # Default hidden
```

## Implementation Tasks

### Phase 1: Update Main.gd Cleanup Method

1. **Update `_clear_right_panel_phase_ui()` method**
   - Add standardized naming patterns to cleanup list
   - Add legacy names for transition period
   - Reset visibility of persistent UI elements
   - Improve logging for debugging

### Phase 2: Refactor Movement Controller (Most Complex)

2. **Refactor MovementController.gd**
   - Remove Section1/Section2/Section3/Section4 naming
   - Create `MovementScrollContainer` > `MovementPanel` structure
   - Move all sections into `MovementPanel`
   - Update cleanup to match new structure
   - Keep all existing functionality intact

### Phase 3: Standardize Other Phase Controllers

3. **Update ShootingController.gd**
   - Already uses good pattern, just ensure consistency
   - Verify ScrollContainer naming
   - Ensure cleanup matches standard pattern

4. **Update ChargeController.gd**
   - Implement standard `ChargeScrollContainer` > `ChargePanel` pattern
   - Update cleanup to match standard pattern

5. **Update FightController.gd**
   - Implement standard `FightScrollContainer` > `FightPanel` pattern
   - Consolidate FightSequence and FightActions under FightPanel
   - Update cleanup to match standard pattern

6. **Update CommandController.gd**
   - Verify standard pattern implementation
   - Ensure naming consistency

7. **Update ScoringController.gd**
   - Verify standard pattern implementation
   - Ensure naming consistency

8. **Check DeploymentController.gd**
   - Verify if right panel is used
   - Implement standard pattern if applicable

### Phase 4: Testing and Validation

9. **Test Phase Transitions**
   - Verify no UI artifacts remain between phases
   - Ensure panel structure is consistent
   - Confirm all functionality preserved

10. **Visual Consistency Check**
    - Verify ScrollContainer sizes are consistent
    - Ensure proper spacing and layout
    - Check that persistent UI (UnitListPanel, UnitCard) behavior is correct

## Existing Patterns to Follow

Reference implementation from `ShootingController.gd:129-228` (already follows good pattern):

```gdscript
func _setup_right_panel() -> void:
    var container = hud_right.get_node_or_null("VBoxContainer")
    if not container:
        container = VBoxContainer.new()
        container.name = "VBoxContainer"
        hud_right.add_child(container)

    # Create scroll container for better layout
    scroll_container = ScrollContainer.new()
    scroll_container.name = "ShootingScrollContainer"  # ✓ Standard naming
    scroll_container.custom_minimum_size = Vector2(250, 400)
    scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
    container.add_child(scroll_container)

    shooting_panel = VBoxContainer.new()
    shooting_panel.name = "ShootingPanel"  # ✓ Standard naming
    shooting_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll_container.add_child(shooting_panel)

    # Add phase-specific UI to shooting_panel
    _create_shooting_ui(shooting_panel)
```

## Error Handling Strategy

1. **Null Checks**: Always verify container existence before manipulation
2. **Graceful Degradation**: If container missing, log error but don't crash
3. **State Validation**: Verify phase state before UI updates
4. **Memory Safety**: Use `queue_free()` for proper cleanup

## Validation Gates

```bash
# Run Godot in headless mode to check for script errors
export PATH="$HOME/bin:$PATH"
timeout 30 godot --headless --quit 2>&1 | grep -i "error\|warning" || echo "No errors found"

# Check for compilation errors in key files
cd 40k
for file in scripts/Main.gd scripts/MovementController.gd scripts/ShootingController.gd scripts/ChargeController.gd scripts/FightController.gd scripts/CommandController.gd scripts/ScoringController.gd; do
    echo "Checking $file..."
    godot --headless --check-only --script $file 2>&1 | grep -i "error" && echo "✗ Errors found in $file" || echo "✓ $file OK"
done
```

## Testing Checklist

- [ ] All phases use consistent ScrollContainer > Panel structure
- [ ] Naming follows `[Phase]ScrollContainer` and `[Phase]Panel` pattern
- [ ] No UI artifacts remain when transitioning between phases
- [ ] Persistent UI elements (UnitListPanel, UnitCard) are properly shown/hidden
- [ ] ScrollContainer sizes are consistent (250x400 minimum)
- [ ] All phase-specific functionality preserved
- [ ] Phase transitions are smooth without flicker
- [ ] Memory cleanup is proper (no leaks)
- [ ] Main.gd cleanup method removes all phase-specific UI

## Detailed Implementation Plan

### MovementController Refactoring (Highest Priority)

Current structure (non-standard):
```
VBoxContainer/
├── Section1_UnitList
├── Section2_UnitDetails
├── Section3_ModeSelection
└── Section4_Actions
```

New structure (standard):
```
VBoxContainer/
└── MovementScrollContainer
    └── MovementPanel
        ├── Section_UnitList (renamed, keep internal structure)
        ├── Section_UnitDetails (renamed, keep internal structure)
        ├── Section_ModeSelection (renamed, keep internal structure)
        └── Section_Actions (renamed, keep internal structure)
```

**Key Changes:**
1. Wrap all sections in `MovementScrollContainer` > `MovementPanel`
2. Rename sections to remove numbers (keep underscore prefix for clarity)
3. Update `_setup_right_panel()` to follow standard pattern
4. Update cleanup in `_exit_tree()` to remove `MovementScrollContainer`

### ScrollContainer Sizing Standard

All phases should use consistent sizing:
```gdscript
scroll_container.custom_minimum_size = Vector2(250, 400)
scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
```

This ensures:
- Minimum width of 250px (fits right panel)
- Minimum height of 400px (adequate space)
- Expands to fill available vertical space
- Consistent appearance across all phases

## References

- Godot 4 UI Best Practices: https://docs.godotengine.org/en/4.4/tutorials/best_practices/
- Container Organization: https://docs.godotengine.org/en/4.4/tutorials/ui/size_and_anchors.html
- Scene Organization: https://docs.godotengine.org/en/4.4/tutorials/best_practices/scene_organization.html
- Issue #101 (Top Panel Standardization): For similar approach and patterns

## Additional Context

The game implements a Warhammer 40K tabletop game with multiple phases. The right panel (HUD_Right) serves as the primary interface for phase-specific actions and information. Maintaining consistency here is crucial for user experience as players interact with different controls throughout gameplay.

Current scene structure (Main.tscn):
```
HUD_Right/VBoxContainer/
├── UnitListPanel (persistent)
└── UnitCard (persistent)
```

Controllers should:
1. Create their ScrollContainer and Panel as children of VBoxContainer
2. Manage visibility of persistent elements based on their needs
3. Clean up their ScrollContainer in `_exit_tree()` (defensive, Main.gd also cleans)
4. Never modify or remove UnitListPanel or UnitCard (only visibility)

## Success Criteria

1. Consistent `[Phase]ScrollContainer` > `[Phase]Panel` structure across all phases
2. No UI artifacts between phase transitions
3. Existing functionality preserved without regression
4. Code follows established patterns in the codebase
5. Clear separation between Main.gd (cleanup) and controller responsibilities
6. Consistent ScrollContainer sizing across phases
7. Proper visibility management of persistent UI elements
8. Improved debuggability with consistent naming

---

**Confidence Score Rationale**: 8/10
- Clear problem identification with specific code locations
- Well-defined solution architecture with detailed naming conventions
- Existing patterns to follow (ShootingController is already good)
- Manageable scope with clear boundaries
- Most complex refactor is MovementController (4 sections to reorganize)
- -2 points for potential edge cases in MovementController refactoring and ensuring all functionality preserved

## Implementation Order

1. **Start**: Update Main.gd cleanup method (lowest risk)
2. **Then**: Update simple controllers (Command, Scoring) to verify pattern works
3. **Then**: Update medium controllers (Charge, Fight)
4. **Then**: Update ShootingController (minor tweaks only)
5. **Finally**: Update MovementController (most complex, do last when pattern proven)

This order minimizes risk by:
- Establishing cleanup first
- Validating pattern on simple controllers
- Tackling most complex controller last when approach is proven
- Allowing early testing of phase transitions
