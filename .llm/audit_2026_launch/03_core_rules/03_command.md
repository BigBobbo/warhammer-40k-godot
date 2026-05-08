# 03.03 — Command Phase

**Read first:** `00_overview.md`, `03_core_rules/README.md`.
**Output:** `.llm/audit_2026_launch/findings/03_03_command.md`

## Scope

Enumerate rules from the Wahapedia Command Phase section. Cover at minimum:
- Battle-shock step: trigger condition (Below Half-Strength), test (2D6 vs Ldr), effects (OC=0, no Actions, no stratagems on/by, auto-fail composure)
- Half-strength definition (multi-model: ≤half starting models; single-model: ≤half starting wounds)
- CP gain (1 per Command phase per current rules; first-turn for player going first)
- 1-CP-per-battle-round-from-other-sources cap
- Faction CP-generating abilities (Sisters Acts of Faith, Imperial Agents, etc.)
- Once-per-battle Command-phase abilities (Oaths of Moment, Dark Pacts, Waaagh!, Martial Ka'tah selection, Acts of Faith, etc.)
- Stratagems flagged for Command phase (cross-check `Stratagems.csv` `phase = Command phase`)
- "Start of your Command phase" triggered abilities (army/detachment/unit-level)

## Codebase entry points

`40k/phases/CommandPhase.gd` (~2178 lines), `40k/autoloads/StratagemManager.gd`, `40k/autoloads/MissionManager.gd`, `40k/autoloads/FactionAbilityManager.gd`, `40k/scripts/StratagemPanel.gd`.

## Live-validation focus

- Reduce a unit below half-strength, advance to next Command phase, confirm Battle-shock test fires
- Battle-shock a unit holding an objective, confirm its OC contribution drops to 0 in scoring
- Attempt to use a stratagem on a Battle-shocked unit, confirm rejection (unless Insane Bravery)
- Trigger Oath of Moment / Waaagh! / Martial Ka'tah and confirm the lock + UI surface

## Prior-audit overlap

Most of this section was verified 2026-05-04 (see `00_overview.md` "Known overlap"). Regression-spot-check:
- Battle-shock 2D6 vs best Leadership — `phases/CommandPhase.gd:693, 799`
- `battle_shocked` flag clears at start of next Command phase — `phases/CommandPhase.gd:201-219`
- FEARLESS / "And They Shall Know No Fear" skip — `phases/CommandPhase.gd:256-289`
- CP first-turn rule (player 1 round 1 = 0 CP, player 2 round 1 = +1 CP) — `phases/CommandPhase.gd:78-85`
- Insane Bravery — `autoloads/StratagemManager.gd:73-99`
- Command Re-roll once-per-phase — `autoloads/StratagemManager.gd:101-127, :662-667`

**Open from prior audit:** no explicit per-round CP-gain cap counter (`cp_gained_this_round[player_id]`). Verify whether multiple CP-granting effects in one round can stack past the cap. If still open, file as `🐛`.

## Output prose

Top 3 launch-blocker Command-phase gaps; top 3 invisible features. Faction-specific Command-phase abilities (Acts of Faith, Sisters CP, etc.) belong here too.
