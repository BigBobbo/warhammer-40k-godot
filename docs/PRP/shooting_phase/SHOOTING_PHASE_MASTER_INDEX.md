# Shooting Phase - Master Implementation Index

## Overview

This document provides a complete index of all Product Requirement Prompts (PRPs) for completing the Warhammer 40K 10th Edition shooting phase implementation.

**Total PRPs:** 24
**Estimated Effort:** See priority categories below

---

## Quick Reference

### By Category

| Category | Count | PRPs |
|----------|-------|------|
| Phase 1: Critical Rules | 5 | PRP-001 to PRP-005 |
| Phase 2: Important Rules | 6 | PRP-010 to PRP-015 |
| Phase 3: Polish Rules | 8 | PRP-020 to PRP-027 |
| Bug Fixes | 4 | PRP-030 to PRP-033 |
| UX Improvements | 4 | PRP-040 to PRP-043 |

### By Priority

| Priority | PRPs |
|----------|------|
| 🔴 Critical | PRP-030, PRP-031, PRP-001, PRP-002, PRP-003, PRP-004, PRP-005 |
| 🟡 High | PRP-010, PRP-011, PRP-012, PRP-013, PRP-014, PRP-015, PRP-040 |
| 🟢 Medium | PRP-020, PRP-021, PRP-032, PRP-041, PRP-042 |
| 🔵 Low | PRP-022 to PRP-027, PRP-033, PRP-043 |

---

## Complete PRP Index

### Phase 1: Critical Rules (Must Have)

These rules are fundamental to 10th edition gameplay.

| ID | Title | Status | Dependencies | File |
|----|-------|--------|--------------|------|
| PRP-001 | Pistol Keyword | ⬜ Pending | None | [Link](phase1_critical/PRP-001_pistol_keyword.md) |
| PRP-002 | Assault Keyword | ⬜ Pending | Movement phase flags | [Link](phase1_critical/PRP-002_assault_keyword.md) |
| PRP-003 | Heavy Keyword | ⬜ Pending | Movement phase flags | [Link](phase1_critical/PRP-003_heavy_keyword.md) |
| PRP-004 | Rapid Fire Keyword | ⬜ Pending | None | [Link](phase1_critical/PRP-004_rapid_fire_keyword.md) |
| PRP-005 | Big Guns Never Tire | ⬜ Pending | PRP-001 (Pistol) | [Link](phase1_critical/PRP-005_big_guns_never_tire.md) |

### Phase 2: Important Rules (Should Have)

These abilities add significant tactical depth.

| ID | Title | Status | Dependencies | File |
|----|-------|--------|--------------|------|
| PRP-010 | Lethal Hits | ⬜ Pending | PRP-031 (Critical Tracking) | [Link](phase2_important/PRP-010_lethal_hits.md) |
| PRP-011 | Sustained Hits | ⬜ Pending | PRP-031 (Critical Tracking) | [Link](phase2_important/PRP-011_sustained_hits.md) |
| PRP-012 | Devastating Wounds | ⬜ Pending | PRP-031 (Critical Tracking) | [Link](phase2_important/PRP-012_devastating_wounds.md) |
| PRP-013 | Blast Keyword | ⬜ Pending | None | [Link](phase2_important/PRP-013_blast_keyword.md) |
| PRP-014 | Torrent Keyword | ⬜ Pending | None | [Link](phase2_important/PRP-014_torrent_keyword.md) |
| PRP-015 | Melta Keyword | ⬜ Pending | None | [Link](phase2_important/PRP-015_melta_keyword.md) |

### Phase 3: Polish Rules (Nice to Have)

Complete the weapon ability set.

| ID | Title | Status | Dependencies | File |
|----|-------|--------|--------------|------|
| PRP-020 | Twin-linked | ⬜ Pending | Wound modifier system | [Link](phase3_polish/PRP-020_twin_linked.md) |
| PRP-021 | Anti-X Keyword | ⬜ Pending | PRP-031 (Critical Tracking) | [Link](phase3_polish/PRP-021_anti_keyword.md) |
| PRP-022 | Hazardous | ⬜ Pending | Mortal wound system | [Link](phase3_polish/PRP-022_hazardous.md) |
| PRP-023 | Indirect Fire | ⬜ Pending | None | [Link](phase3_polish/PRP-023_indirect_fire.md) |
| PRP-024 | Ignores Cover | ⬜ Pending | PRP-030 (Cover Fix) | [Link](phase3_polish/PRP-024_ignores_cover.md) |
| PRP-025 | Lance Keyword | ⬜ Pending | Wound modifier system | [Link](phase3_polish/PRP-025_lance_keyword.md) |
| PRP-026 | Precision | ⬜ Pending | PRP-031 (Critical Tracking) | [Link](phase3_polish/PRP-026_precision.md) |
| PRP-027 | One Shot | ⬜ Pending | None | [Link](phase3_polish/PRP-027_one_shot.md) |

### Bug Fixes

Fix existing issues before adding new features.

| ID | Title | Status | Severity | File |
|----|-------|--------|----------|------|
| PRP-030 | Cover Logic Fix | ⬜ Pending | HIGH | [Link](bugfixes/PRP-030_cover_logic_fix.md) |
| PRP-031 | Critical Hit Tracking | ⬜ Pending | HIGH (Blocker) | [Link](bugfixes/PRP-031_critical_hit_tracking.md) |
| PRP-032 | Dice Context Fix | ⬜ Pending | MEDIUM | [Link](bugfixes/PRP-032_dice_context_fix.md) |
| PRP-033 | Debug Logging Cleanup | ⬜ Pending | LOW | [Link](bugfixes/PRP-033_debug_logging_cleanup.md) |

### UX Improvements

Enhance the player experience.

| ID | Title | Status | Priority | File |
|----|-------|--------|----------|------|
| PRP-040 | Quick Assign Weapons | ⬜ Pending | HIGH | [Link](ux_improvements/PRP-040_quick_assign_weapons.md) |
| PRP-041 | Weapon Tooltips | ⬜ Pending | MEDIUM | [Link](ux_improvements/PRP-041_weapon_tooltips.md) |
| PRP-042 | Target Validation Indicators | ⬜ Pending | MEDIUM | [Link](ux_improvements/PRP-042_target_validation_indicators.md) |
| PRP-043 | Keyboard Shortcuts | ⬜ Pending | LOW | [Link](ux_improvements/PRP-043_keyboard_shortcuts.md) |

---

## Dependency Graph

```
PRP-030 (Cover Fix)
    └── PRP-024 (Ignores Cover)

PRP-031 (Critical Hit Tracking)  ← BLOCKER - Implement First!
    ├── PRP-010 (Lethal Hits)
    ├── PRP-011 (Sustained Hits)
    ├── PRP-012 (Devastating Wounds)
    ├── PRP-021 (Anti-X)
    └── PRP-026 (Precision)

PRP-001 (Pistol)
    └── PRP-005 (Big Guns Never Tire)

Movement Phase Flags (External)
    ├── PRP-002 (Assault) - needs `advanced` flag
    └── PRP-003 (Heavy) - needs `remained_stationary` flag

Wound Modifier System (New)
    ├── PRP-020 (Twin-linked)
    └── PRP-025 (Lance)

Mortal Wound System (New)
    └── PRP-022 (Hazardous)
```

---

## Recommended Implementation Order

### Sprint 1: Foundation (Bug Fixes + Infrastructure)
1. ✅ PRP-030 - Cover Logic Fix
2. ✅ PRP-031 - Critical Hit Tracking
3. ✅ PRP-032 - Dice Context Fix

### Sprint 2: Core Keywords
4. ✅ PRP-001 - Pistol Keyword
5. ✅ PRP-004 - Rapid Fire Keyword
6. ✅ PRP-003 - Heavy Keyword
7. ✅ PRP-002 - Assault Keyword
8. ✅ PRP-005 - Big Guns Never Tire

### Sprint 3: Critical Abilities
9. ✅ PRP-010 - Lethal Hits
10. ✅ PRP-011 - Sustained Hits
11. ✅ PRP-012 - Devastating Wounds

### Sprint 4: Tactical Abilities
12. ✅ PRP-013 - Blast Keyword
13. ✅ PRP-014 - Torrent Keyword
14. ✅ PRP-015 - Melta Keyword

### Sprint 5: UX + Polish
15. ✅ PRP-040 - Quick Assign Weapons
16. ✅ PRP-041 - Weapon Tooltips
17. ✅ PRP-042 - Target Validation Indicators

### Sprint 6: Remaining Abilities
18-24. Remaining Phase 3 PRPs as time permits

---

## Files Modified Summary

| File | PRPs Affecting |
|------|----------------|
| `RulesEngine.gd` | All PRPs (primary) |
| `ShootingPhase.gd` | PRP-001, 002, 003, 005, 033 |
| `ShootingController.gd` | PRP-040-043, 033 |
| `SaveDialog.gd` | PRP-012, 030 |
| `MovementPhase.gd` | PRP-002, 003 (flags) |

---

## Testing Checklist

For each implemented PRP:
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed
- [ ] Multiplayer sync verified
- [ ] No regressions in existing functionality
- [ ] Documentation updated

---

## Status Legend

| Symbol | Meaning |
|--------|---------|
| ⬜ | Pending |
| 🔄 | In Progress |
| ✅ | Complete |
| ❌ | Blocked |

---

## Notes

- Start with Bug Fixes (PRP-030, PRP-031) as they unblock multiple features
- Verify Movement phase sets required flags before implementing PRP-002, PRP-003
- Create wound modifier system when implementing PRP-020 or PRP-025
- Consider implementing mortal wound system with PRP-022

---

*Last Updated: 2025-01-27*
