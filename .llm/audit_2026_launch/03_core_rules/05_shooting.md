# 03.05 — Shooting Phase

**Read first:** `00_overview.md`, `03_core_rules/README.md`.
**Output:** `.llm/audit_2026_launch/findings/03_05_shooting.md`

This file covers the **shooting sequence**. The per-token weapon-ability audit lives in `04_data_entities/02_weapon_rules.md` — do not duplicate it here. This audit verifies the *attack pipeline* in which those tokens fire.

## Scope

Enumerate rules from the Wahapedia Shooting Phase section. Cover at minimum:
- Eligibility: not after Advance (unless Assault), not after Fall Back, not in ER (except Pistol or Big Guns Never Tire), not Battle-shocked
- Big Guns Never Tire: MONSTER/VEHICLE shoot in ER at -1 BS; can target the unit they're in ER with or another visible unit
- Splitting fire across weapons
- Pistols: if any model in unit is in ER, that model can only shoot Pistols, and only Pistol weapons in unit may shoot
- Look Out, Sir: targeting protection for CHARACTERS — exact 10e criteria from Wahapedia (not 9e wounds-threshold)
- Indirect Fire targeting: visible vs. not-visible behaviour, -1 BS, +1 cover when not visible, no CHARACTER targeting unless visible
- Hit roll → Wound roll → Save → Damage → FNP sequence (full pipeline)
- Modifier cap ±1 final at each step
- Critical Hit / Critical Wound on unmodified 6
- Cover save +1 (cap 3+ for INFANTRY/BEAST/SWARM); invuln cannot be modified by AP
- Damage allocation to wounded model first; mortal wound spillover within unit
- Out-of-sequence stratagems / abilities (Go to Ground, Smokescreen, Counter-fire reactive)

## Codebase entry points

`40k/phases/ShootingPhase.gd`, `40k/scripts/ShootingController.gd`, `40k/autoloads/RulesEngine.gd` (attack pipeline), `40k/autoloads/EffectPrimitives.gd`, `40k/scripts/WoundAllocationOverlay.gd`, `40k/scripts/WeaponKeywordIcons.gd`.

## Live-validation focus

- Attempt to shoot after Advance with a non-Assault weapon → reject
- Shoot a CHARACTER while a non-CHARACTER ≥3-model unit is closer → LOS! redirects
- Indirect Fire at a target with no LoS → -1 BS, target gets +1 cover, CHARACTER cannot be targeted
- Big Guns Never Tire: VEHICLE in ER fires at the unit it's in ER with → -1 to hit
- Stack Heavy + cover + Stealth on a target → confirm ±1 cap holds
- Allocate damage to wounded model → confirm correct ordering
- Trigger Go to Ground reactive after target select → confirm timing window honoured

## Prior-audit overlap

Heavily covered by 2026-05 audit and `SHOOTING_PHASE_AUDIT.md`. Regression-spot-check:
- Look Out, Sir 10e behaviour (no 9e wounds-threshold; standalone-character protection via Lone Operative only) — `RulesEngine.gd`
- Cover save 3+ cap INFANTRY/BEAST/SWARM only — `RulesEngine.gd:3674-3704`
- Indirect Fire automatic cover override — `RulesEngine.gd:3036`
- Dual resolution paths sync (auto-resolve mirrors interactive) — `T3-17` in MASTER_AUDIT
- One Shot weapon keyword — `T4-2`
- Go to Ground / Smokescreen — `T4-6`
- BLAST engagement-of-friendlies block — `EXPLOSIVE CLEARANCE` stratagem aside

## Output prose

Top 3 launch-blocker Shooting-phase gaps; top 3 invisible features. Pay attention to the seam between `_resolve_assignment()` (auto) and the interactive flow — drift between them has been a recurring bug class.
