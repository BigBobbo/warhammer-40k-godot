# 03.12 — Battle-shock Cascade

**Read first:** `00_overview.md`, `03_core_rules/README.md`.
**Output:** `.llm/audit_2026_launch/findings/03_12_battle_shock.md`

## Scope

Battle-shock effects propagate across phases. The state itself is owned by Command phase; the cascades are everywhere. Audit each touchpoint:
- OC = 0 in objective scoring (Mission)
- Cannot perform Actions (Action system)
- Cannot use Stratagems on/by Battle-shocked unit (StratagemManager)
- Cannot perform composure-style tests / auto-fail (Wahapedia rule text)
- Desperate Escape threshold becomes 1-3 instead of 1-2 (Movement)
- Per-faction abilities that key off Battle-shocked status (e.g., Daemons benefit, certain stratagems target Battle-shocked enemies)
- UI surfacing: Battle-shocked indicator on the unit, panel state, hover tooltip
- Recovery at start of next Command phase

## Codebase entry points

`40k/autoloads/MissionManager.gd:207-209`, `40k/autoloads/StratagemManager.gd:603, 613`, `40k/phases/CommandPhase.gd:201-219, 256-289, 693, 799`, `40k/phases/MovementPhase.gd:4879-4888`, `40k/autoloads/SecondaryMissionManager.gd:1553`.

## Live-validation focus

- Battle-shock a unit, attempt to use a Stratagem on it → reject (unless Insane Bravery)
- Battle-shock a unit, attempt to perform an Action → reject
- Fall Back a Battle-shocked unit → confirm 1-3 Desperate Escape threshold
- Score with Battle-shocked unit on objective → no OC contribution
- Battle-shocked indicator visible in UI

## Prior-audit overlap

Substantially verified 2026-05. Regression spot-check only. The notable open item: stacking CP-gain caps per round.

## Output prose

Top 3 launch-blocker cascade gaps; top 3 invisible features. Faction abilities that explicitly *target* Battle-shocked enemies (auto-wound them, etc.) are a high-likelihood invisible-feature surface — flag any whose code is `C` but has no UI/data trigger.
