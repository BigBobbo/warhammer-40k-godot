# 03.04 — Movement Phase

**Read first:** `00_overview.md`, `03_core_rules/README.md`.
**Output:** `.llm/audit_2026_launch/findings/03_04_movement.md`

## Scope

Enumerate rules from the Wahapedia Movement Phase section. Cover at minimum:
- Movement step: Normal Move (≤M), Advance (M+D6, no shoot/charge unless Assault), Fall Back (must end >ER, no shoot/charge unless ability says, cannot end on Reinforcements zones), Remain Stationary (Heavy bonus eligibility)
- Cannot move within ER except during Charge / Pile-In / Consolidate
- Coherency required at end of every move
- Cannot move through models (friendly or enemy) unless FLY; FLY may move over but must end legal
- Terrain traversal: 1" horizontal+vertical = 1" of M
- Ruin walls: cannot pass through unless ability says; INFANTRY/BEAST/SWARM may climb; upper-floor occupancy restrictions
- Ending on terrain features (only floors of Ruins for INFANTRY; FLY for upper)
- Reinforcements step: Deep Strike >9" from enemy; T1 restriction per mission pack
- Strategic Reserves arrival (T2+ within 6" of board edge, ≥9" from enemy)
- Rapid Ingress stratagem (end of opponent's Movement phase)
- Desperate Escape: D6 per model when Falling Back through enemies; 1-2 fail (1-3 if Battle-shocked)
- Towering keyword interactions
- Embark / Disembark from Transports (datasheet rules)
- End-of-Movement triggered abilities

## Codebase entry points

`40k/phases/MovementPhase.gd`, `40k/scripts/MovementController.gd`, `40k/autoloads/Measurement.gd`, `40k/autoloads/TerrainManager.gd`, `40k/autoloads/EnhancedLineOfSight.gd`, `40k/autoloads/TransportFactory.gd`.

## Live-validation focus

- Advance a unit and immediately attempt to charge/shoot non-Assault → confirm rejection
- Fall Back through an enemy unit with ≥1 model in original ER and confirm Desperate Escape triggers; confirm 1-3 threshold when Battle-shocked
- Place a non-FLY unit on the upper floor of a Ruin → confirm rejection
- Deep Strike a Reserves unit at exactly 9" → confirm fails (must be > 9")
- Rapid Ingress at end of opponent's Movement phase

## Prior-audit overlap

Spot-check and confirm:
- Difficult terrain `difficult_ground` 2"/piece penalty, FLY ignores — `MOVEMENT_PHASE_AUDIT.md §2.7`
- Disembarked-this-phase Heavy bonus block — `MOVEMENT_PHASE_AUDIT.md §2.12`
- Desperate Escape battle-shocked 1-3 threshold — `phases/MovementPhase.gd:4879-4888`

## Output prose

Top 3 launch-blocker Movement gaps; top 3 invisible features. Watch for Aircraft / Hover / Towering rules that have datasheet support but no movement-controller branch.
