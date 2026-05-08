# 03.01 — Pre-game & Setup

**Read first:** `00_overview.md`, `03_core_rules/README.md`.
**Output:** `.llm/audit_2026_launch/findings/03_01_pregame.md`

## Scope

Audit the pre-game phase of 10e: army construction through end of deployment.

Enumerate rules from these Wahapedia sections (don't work from a hand-list):
- Pre-game / Mustering an Army
- Determining the Mission
- Declare Battle Formations (Reserves, Strategic Reserves, Reinforcements with Deep Strike, Infiltrators, Scouts pre-game move)
- Deployment
- Determine first turn / roll-off

Cover at minimum (extend with anything else on the page):
- Battle size brackets (Combat Patrol / Incursion / Strike Force / Onslaught) and points caps
- Detachment selection (one per army; enhancement caps per battle size)
- Warlord designation
- Enhancements: max per army, one per CHARACTER, +pts cost
- Mission selection (mission deck or fixed mission)
- Deployment map selection
- Terrain placement (player or pre-set)
- Determining attacker/defender via roll-off
- Strategic Reserves (≤25% pts at start of game; arrival rules)
- Reserves with Deep Strike (>9" from enemy on arrival; turn-1 restriction per current mission pack)
- Infiltrators (set up >9" from enemy DZ and ER, anywhere not in enemy DZ)
- Scouts X" (pre-game move declared after deployment, before first turn)
- Deployment alternation; finishing condition
- First turn determination per mission pack

## Codebase entry points

`40k/phases/DeploymentPhase.gd`, `40k/phases/RollOffPhase.gd`, `40k/phases/ScoutPhase.gd`, `40k/phases/ScoutMovesPhase.gd`, `40k/autoloads/MissionManager.gd`, `40k/autoloads/ArmyListManager.gd`, `40k/scripts/MainMenu.gd`, `40k/dialogs/FixedMissionSelectionDialog.gd`, `40k/deployment_zones/`.

## Live-validation focus

Drive ≥ 2 of these through MCP:
- Place a unit in Strategic Reserves at army-build time and confirm it does not deploy on T1
- Trigger a Scouts pre-game move and confirm the unit can move ≤ its Scouts value, ending >9" from any enemy unit
- Attempt to take an Enhancement on a non-CHARACTER and confirm the validator rejects/warns

## Prior-audit overlap

- Roll-off attacker/defender role storage — verified 2026-05-04 in `phases/RollOffPhase.gd:184-194`
- Enhancement validator (1-per-CHARACTER, 1-of-each, bearer must be CHARACTER) — verified 2026-05-04 in `autoloads/ArmyListManager.gd:1275-1304`

Regression-spot-check these and confirm `✅ VERIFIED (regression spot-check)` rather than refiling.

## Output prose

Top 3 launch-blocker pre-game gaps; top 3 invisible features (e.g., a Battle Formation supported by code but not exposed in deployment UI).
