# 03.08 — End of Turn

**Read first:** `00_overview.md`, `03_core_rules/README.md`.
**Output:** `.llm/audit_2026_launch/findings/03_08_end_of_turn.md`

## Scope

End-of-turn structure is small but easy to get wrong. Cover:
- End-of-turn triggered abilities (some datasheets/detachments fire here)
- Battle-shock recovery happens in next Command phase, not end of turn — confirm the flag persists across the boundary
- Primary scoring per current mission pack (Leviathan / Pariah Nexus / Chapter Approved — identify which is encoded)
- OC=0 Battle-shocked still prevents scoring at end of turn
- Round-5 game-end and tiebreaker rules
- Turn pass-through state cleanup (per-turn flags reset, "this turn" durations expire)

## Codebase entry points

`40k/phases/ScoringPhase.gd`, `40k/autoloads/MissionManager.gd`, `40k/autoloads/PhaseManager.gd`, `40k/autoloads/GameManager.gd`, `40k/phases/CommandPhase.gd:201-219` (clear of `battle_shocked`).

## Live-validation focus

- Trigger an end-of-turn ability that exists on some unit datasheet (e.g., a faction-specific "at the end of your turn" effect) — confirm it fires
- Score primary at end of turn while a unit on the objective is Battle-shocked → unit doesn't contribute OC
- Round-5 game-end → no further turns dispatched

## Prior-audit overlap

- Round-5 game-end — verified 2026-05
- Battle-shock OC=0 in scoring — verified 2026-05

## Output prose

Top 3 launch-blocker end-of-turn gaps; top 3 invisible features. Particularly: per-turn flags that should reset but don't (`charged_this_turn`, `advanced_this_turn`, `fell_back_this_turn`).
