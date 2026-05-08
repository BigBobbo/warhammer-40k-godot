# 03.10 — Objectives & Scoring

**Read first:** `00_overview.md`, `03_core_rules/README.md`.
**Output:** `.llm/audit_2026_launch/findings/03_10_objectives.md`

## Scope

Enumerate from the Wahapedia mission rules + current mission pack (Leviathan / Pariah Nexus / Chapter Approved — identify which is encoded). Cover:
- OC contests: sum OC of all eligible models within range of objective
- Battle-shock OC=0 → no contribution
- Sticky objectives (note: this is faction/detachment-specific, not core)
- Primary scoring rules per encoded mission pack
- Secondary scoring: Fixed and Tactical pools, per-turn rules, discard-for-CP
- Objective control change events (visual feedback)
- Mission-specific objective behaviours (engagement-zoom etc.)

## Codebase entry points

`40k/autoloads/MissionManager.gd`, `40k/autoloads/SecondaryMissionManager.gd`, `40k/scripts/SecondaryMissionPanel.gd`, `40k/dialogs/FixedMissionSelectionDialog.gd`, `40k/phases/ScoringPhase.gd`, `40k/scripts/ObjectiveVisual.gd`, `40k/deployment_zones/*.json`.

## Live-validation focus

- Battle-shock a unit with high OC sitting on an objective → confirm OC contribution drops to 0 in scoring (regression of 2026-05 verification)
- Score primary at end of turn → confirm correct points per mission pack
- Discard a Tactical secondary for +1 CP via DISCARD_SECONDARY → confirm CP gain
- Sticky objective: a faction with sticky takes an objective and leaves → confirm it still scores

## Prior-audit overlap

- Battle-shock OC=0 — `MissionManager.gd:207-209` (verified 2026-05)
- USE_NEW_ORDERS / DISCARD_SECONDARY for Crucible mission management — verified 2026-05
- Secondary mission discard logic — `T7-47`
- Objective control flash on change — `T7-39`

`SECONDARY_MISSIONS_TASKS.md` is the existing task list; reference its IDs.

## Output prose

Top 3 launch-blocker scoring gaps; top 3 invisible features. Particularly: secondary missions whose code path exists but has no UI affordance to select them, or mission-pack-specific rules (Pariah Nexus terrain placements) that diverge from the encoded version.
