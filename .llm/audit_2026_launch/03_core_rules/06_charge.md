# 03.06 — Charge Phase

**Read first:** `00_overview.md`, `03_core_rules/README.md`.
**Output:** `.llm/audit_2026_launch/findings/03_06_charge.md`

## Scope

Enumerate rules from the Wahapedia Charge Phase section. Cover at minimum:
- Eligibility: not after Advance / Fall Back, not Reinforcements turn-1 per pack, not Battle-shocked, not already in ER (cannot charge into existing ER)
- Declare targets (one or more, all within 12")
- Charge roll = 2D6
- Move each model up to roll; must end in ER of every declared target
- Coherency at end of move
- Cannot move into ER of any unit not declared
- Cannot move through other models
- Charging unit gets Fights First that turn
- Overwatch stratagem (1 CP, BS5+ regardless of normal hit modifiers, fired by a unit being declared as a charge target)
- Heroic Intervention 10e Core Strategic Ploy (1 CP, opponent's Charge phase) — verified working in 2026-05 audit
- Tank Shock stratagem
- Out-of-phase abilities triggered by charge declaration

## Codebase entry points

`40k/phases/ChargePhase.gd`, `40k/scripts/ChargeController.gd`, `40k/autoloads/StratagemManager.gd`, `40k/scripts/ChargeArrowVisual.gd`.

## Live-validation focus

- Declare two charge targets, roll low enough to reach only one → reject (must reach all)
- Charge into ER of an undeclared unit during the charge move → reject
- Heroic Intervention end-of-charge timing → unit moves up to 6" toward charging unit
- Fire Overwatch on charge declaration → BS5+ regardless of modifiers
- Tank Shock after vehicle charge — verify 2026-05 timing window holds

## Prior-audit overlap

- Heroic Intervention is a 10e Core Strategic Ploy (1 CP) — verified `StratagemManager.gd:272-298, 302-328` and `ChargePhase.gd:486-516, 2706-2985`
- Multi-target charge declarations work — `T7-50`
- Overwatch risk assessment plumbed in AI — `T7-51`
- Counter-Offensive — `T7-32`

## Output prose

Top 3 launch-blocker Charge gaps; top 3 invisible features. Watch for charge-roll modifiers (e.g., re-roll-charge stratagems, +1 charge auras) that may not be wired into the dice pipeline.
