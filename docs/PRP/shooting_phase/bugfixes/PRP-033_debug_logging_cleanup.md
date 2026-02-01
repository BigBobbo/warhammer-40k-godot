# PRP-033: Debug Logging Cleanup

## Context

The shooting phase contains excessive debug logging (~200 print statements) with decorative box-drawing characters. This clutters output and impacts performance.

**Severity:** LOW - Code quality improvement

---

## Problem Statement

ShootingPhase.gd contains extensive debug logging:
```gdscript
print("╔═══════════════════════════════════════════════════════════════")
print("║ ShootingPhase._validate_complete_shooting_for_unit() CALLED")
print("║ Unit ID: ", unit_id)
print("╚═══════════════════════════════════════════════════════════════")
```

Issues:
1. Performance overhead from string concatenation
2. Cluttered console output
3. Hard to find actual errors
4. Box-drawing characters don't render well in all terminals

---

## Solution Overview

1. Add debug flag constant to control verbose logging
2. Wrap debug prints in conditional
3. Use DebugManager if it exists
4. Keep error-level logs always visible

---

## Implementation

```gdscript
# At top of ShootingPhase.gd
const DEBUG_SHOOTING = false  # Set true for verbose logging

func _process_select_shooter(action: Dictionary) -> Dictionary:
    if DEBUG_SHOOTING:
        DebugManager.log_phase("ShootingPhase", "_process_select_shooter called", {
            "unit_id": action.get("actor_unit_id", "")
        })

    # ... actual logic ...
```

---

## Guidelines

### Keep Always
- Error messages
- Warning messages
- State change notifications (to log file only)

### Wrap in DEBUG flag
- Method entry/exit logging
- Intermediate state dumps
- Signal emission logs
- Validation step details

### Remove Entirely
- Redundant confirmation prints
- Decorative box-drawing logs
- "DEBUG:" prefixed temporary logs

---

## Implementation Tasks

- [ ] Add DEBUG_SHOOTING constant
- [ ] Grep for all print statements in ShootingPhase.gd
- [ ] Categorize each print (keep/wrap/remove)
- [ ] Wrap verbose logs in DEBUG_SHOOTING check
- [ ] Remove decorative box-drawing characters
- [ ] Use DebugManager.log_phase() where appropriate
- [ ] Test that errors still appear in non-debug mode
- [ ] Apply same pattern to ShootingController.gd
