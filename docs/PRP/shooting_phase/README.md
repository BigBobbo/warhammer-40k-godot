# Shooting Phase - Product Requirement Prompts

## Overview

This directory contains Product Requirement Prompts (PRPs) for completing and improving the Warhammer 40K 10th Edition shooting phase implementation.

## Current Status

The shooting phase has a **solid foundation** with:
- Core hit/wound/save mechanics
- Interactive save resolution
- Multi-weapon sequencing
- Base-aware line of sight
- Basic cover system

However, critical 10th edition weapon abilities and rules are missing.

---

## Directory Structure

```
shooting_phase/
├── README.md                    # This file
├── phase1_critical/             # Must-have rules for 10e compliance
│   ├── PRP-001_pistol_keyword.md
│   ├── PRP-002_assault_keyword.md
│   ├── PRP-003_heavy_keyword.md
│   ├── PRP-004_rapid_fire_keyword.md
│   └── PRP-005_big_guns_never_tire.md
├── phase2_important/            # Important abilities for full gameplay
│   ├── PRP-010_lethal_hits.md
│   ├── PRP-011_sustained_hits.md
│   ├── PRP-012_devastating_wounds.md
│   ├── PRP-013_blast_keyword.md
│   ├── PRP-014_torrent_keyword.md
│   └── PRP-015_melta_keyword.md
├── phase3_polish/               # Nice-to-have abilities
│   ├── PRP-020_twin_linked.md
│   ├── PRP-021_anti_keyword.md
│   ├── PRP-022_hazardous.md
│   ├── PRP-023_indirect_fire.md
│   ├── PRP-024_ignores_cover.md
│   ├── PRP-025_lance_keyword.md
│   ├── PRP-026_precision.md
│   └── PRP-027_one_shot.md
├── bugfixes/                    # Bug fixes and code quality
│   ├── PRP-030_cover_logic_fix.md
│   ├── PRP-031_critical_hit_tracking.md
│   ├── PRP-032_dice_context_fix.md
│   └── PRP-033_debug_logging_cleanup.md
└── ux_improvements/             # User experience enhancements
    ├── PRP-040_quick_assign_weapons.md
    ├── PRP-041_weapon_tooltips.md
    ├── PRP-042_target_validation_indicators.md
    └── PRP-043_keyboard_shortcuts.md
```

---

## Implementation Order

### Recommended Sequence

1. **Bug Fixes First** - Fix cover logic and critical hit tracking before adding new abilities
2. **Phase 1 Critical** - Pistol, Assault, Heavy, Rapid Fire enable core 10e gameplay
3. **Phase 2 Important** - Lethal/Sustained/Devastating Hits add tactical depth
4. **UX Improvements** - Improve usability alongside rule additions
5. **Phase 3 Polish** - Complete remaining abilities

### Dependencies

```
PRP-031 (Critical Hit Tracking)
    └── Required by: PRP-010, PRP-011, PRP-012, PRP-021

PRP-030 (Cover Fix)
    └── Required by: PRP-024 (Ignores Cover)

PRP-001 (Pistol) + PRP-005 (Big Guns Never Tire)
    └── Together enable engagement range shooting
```

---

## Related Files

| File | Purpose |
|------|---------|
| `40k/phases/ShootingPhase.gd` | Phase state machine |
| `40k/scripts/ShootingController.gd` | UI controller |
| `40k/autoloads/RulesEngine.gd` | Rules resolution |
| `40k/autoloads/EnhancedLineOfSight.gd` | LoS calculation |
| `40k/scripts/SaveDialog.gd` | Save resolution UI |

---

## Reference Documentation

- [Wahapedia Core Rules](https://wahapedia.ru/wh40k10ed/the-rules/core-rules/)
- [Wahapedia Weapon Abilities](https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Weapon-Abilities)

---

## Tracking Progress

Each PRP includes an implementation checklist. Update these as you complete items:

```markdown
## Implementation Tasks
- [x] Completed task
- [ ] Pending task
```

Use `/clear` between implementing different PRPs to manage context.
