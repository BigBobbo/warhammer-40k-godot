# Project Task List

All tasks are now tracked in the consolidated **MASTER_AUDIT.md** at the project root.

See: `/home/user/warhammer-40k-godot/MASTER_AUDIT.md`

This file contains 128 open items across 6 priority tiers, covering all phases (Command, Movement, Deployment, Shooting, Charge, Fight, Mathhammer) plus testing infrastructure.

## Active Tasks

- [ ] **T1-9 [MH-BUG-1] Mathhammer damage extraction is fundamentally broken** — `_extract_damage_from_result()` only counts model kills as 1 damage each, ignoring actual wound deltas. A lascannon dealing 6 damage to a 12W vehicle that doesn't die counts as 0 damage. All average damage, kill probability, and efficiency outputs are wrong. Fix: compute actual wound delta from diffs (old wounds - new wounds) instead of checking `new_wounds == 0`. **Files:** `Mathhammer.gd:232-240`
