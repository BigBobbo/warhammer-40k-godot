# 03.07 — Fight Phase

**Read first:** `00_overview.md`, `03_core_rules/README.md`.
**Output:** `.llm/audit_2026_launch/findings/03_07_fight.md`

## Scope

Enumerate rules from the Wahapedia Fight Phase section. Cover at minimum:
- Fights First / Strikes First / Strikes Last layered ordering
- "Eligible to fight" definition (within ER OR within 2" of friendly already in ER)
- Pile In: up to 3" toward closest enemy, must end no further from closest enemy than start; cannot end ER of new unit it wasn't already
- Selecting weapon profile per model (multiple melee weapons cannot combine attacks except Extra Attacks)
- Make Attacks: WS for hit, S vs T for wound; cover does NOT apply to melee saves
- Lance: +1 to wound on a charge that turn
- All ranged-style abilities apply where the weapon profile lists them (Twin-linked, Lethal Hits, Sustained Hits, etc.)
- Consolidation: 3" toward closest enemy unit OR objective marker
- Remove destroyed models before consolidation
- Battle-shocked interaction with pile-in / fight eligibility (verify Wahapedia text)
- Mandatory consolidation FAQ
- Fights-First stacking (charging unit + Fights First ability)

## Codebase entry points

`40k/phases/FightPhase.gd`, `40k/scripts/FightController.gd`, `40k/autoloads/RulesEngine.gd` (melee attack pipeline), `40k/scripts/MeleeWeaponSelector.gd` (if exists), `40k/dialogs/FightSelectionDialog.gd`.

## Live-validation focus

- Charging unit fights before non-charging non-Fights-First → confirm activation order
- Two units with Fights First, alternating starting with active player
- Pile in to ER of an undeclared adjacent unit → reject
- Lance: charge attack vs. non-charge attack on same unit → +1 to wound only on charge
- Consolidate 3" toward objective rather than closest enemy → allowed per 10e
- Fights First + Strikes Last interaction (e.g., charging unit with both keywords)

## Prior-audit overlap

- Fight-selection dialog sync race fix for remote player — `T3-13` in MASTER_AUDIT
- Per-model fight eligibility validation — `phases/FightPhase.gd:_validate_assign_attacks` (verified 2026-05)
- Multi-weapon melee optimization — `T7-28`
- Mandatory consolidation FAQ — verified 2026-05

## Output prose

Top 3 launch-blocker Fight-phase gaps; top 3 invisible features. Pay attention to whether weapon-keyword handlers in melee match the shooting handlers exactly (a single helper should resolve both).
