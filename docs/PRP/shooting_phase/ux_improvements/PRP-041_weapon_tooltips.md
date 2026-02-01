# PRP-041: Weapon Profile Tooltips

## Context

Currently, weapon stats are not easily visible during target assignment. Players must remember weapon profiles or reference external sources.

**Priority:** MEDIUM - Usability improvement

---

## Problem Statement

When selecting weapons in the shooting UI:
- Only weapon name is shown
- No stats visible (range, attacks, S, AP, D)
- No special rules shown
- Players must memorize or guess weapon capabilities

---

## Solution Overview

Add hover tooltips to weapon items that display full weapon profile:
- Range
- Attacks
- BS (Ballistic Skill)
- Strength
- AP
- Damage
- Special Rules / Keywords

---

## User Stories

- **US1:** As a player, I want to see weapon stats by hovering so I can make informed targeting decisions.
- **US2:** As a new player, I want to learn weapon profiles without external references.
- **US3:** As any player, I want to see special rules like Rapid Fire range clearly.

---

## Technical Requirements

### Tooltip Content
```
┌── Bolt Rifle ──────────────────┐
│ Range: 24"   Attacks: 2        │
│ BS: 3+       Strength: 4       │
│ AP: -1       Damage: 1         │
│                                │
│ Keywords: RAPID FIRE 1         │
│ Half Range: 12" (+1 attack)    │
└────────────────────────────────┘
```

### Implementation Options

1. **Native Godot Tooltip:**
   ```gdscript
   weapon_item.set_tooltip_text(_format_weapon_tooltip(weapon_id))
   ```

2. **Custom Popup Panel:**
   - More control over styling
   - Can include icons
   - Better positioning

### Code Changes

```gdscript
# ShootingController.gd

func _format_weapon_tooltip(weapon_id: String) -> String:
    var profile = RulesEngine.get_weapon_profile(weapon_id)
    var tooltip = ""
    tooltip += "Range: %d\"   Attacks: %d\n" % [profile.range, profile.attacks]
    tooltip += "BS: %d+       Strength: %d\n" % [profile.bs, profile.strength]
    tooltip += "AP: %d        Damage: %d\n" % [profile.ap, profile.damage]

    var keywords = profile.get("keywords", [])
    if not keywords.is_empty():
        tooltip += "\nKeywords: " + ", ".join(keywords)

    var special = profile.get("special_rules", "")
    if special != "":
        tooltip += "\n" + special

    return tooltip
```

---

## Acceptance Criteria

- [ ] Hovering over weapon shows tooltip with stats
- [ ] All relevant stats displayed (Range, A, BS, S, AP, D)
- [ ] Keywords shown (Rapid Fire, Heavy, etc.)
- [ ] Special rules shown
- [ ] Tooltip positioned to not block view
- [ ] Tooltip dismisses on mouse leave
- [ ] Works in weapon tree UI

---

## Implementation Tasks

- [ ] Create `_format_weapon_tooltip()` function
- [ ] Add tooltips to weapon tree items
- [ ] Style tooltip for readability
- [ ] Include keyword indicators ([RF], [H], etc.)
- [ ] Calculate and show half-range for Rapid Fire
- [ ] Test with various weapon types
