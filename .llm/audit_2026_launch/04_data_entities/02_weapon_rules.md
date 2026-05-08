# 04.02 — Weapon Special Rules

**Read first:** `00_overview.md`, `01_inventory.md`, `04_data_entities/README.md`, `universe/weapon_rules.json`.
**Output:** `.llm/audit_2026_launch/findings/04_02_weapon_rules.md`

## Scope

37 distinct weapon-rule tokens in the catalog. 19 used by active rosters (P0). 18 catalog-only (P2 — including `conversion`, `one shot`, `plasma warhead`, `sustained hits d3`, `rapid fire d3/d6/d6+3`, `bubblechukka`, `c'tan power`, `dead choppy`, `harpooned`, `hooked`, `impaled`, `linked fire`, `overcharge`, `psychic assassin`, `reverberating summons`, `snagged`).

For each token: find the handler in `40k/autoloads/RulesEngine.gd` (attack pipeline). Token must be applied at the correct dice step:
- Hit step: Lethal Hits, Sustained Hits, Twin-linked, Torrent (auto-hits → skip), Heavy (+1 if stationary), Indirect Fire (-1)
- Wound step: Anti-X, Devastating Wounds, Lance (charge melee +1)
- Save step: Ignores Cover, Hazardous (post-attack)
- Damage step: Melta, Devastating Wounds (mortal damage)
- Allocation: Precision
- Eligibility: Pistol, Assault, Blast, Rapid Fire, One Shot, Extra Attacks
- Other: Indirect Fire (cover override, character-targeting), Torrent (no LoS needed)

For each token, check:
1. Wahapedia rule text vs. implementation behaviour (cite divergence)
2. Whether it works **only** in shooting, **only** in melee, or both — many tokens (Lethal Hits, Sustained Hits, Twin-linked) apply in both phases
3. Whether the icon / tooltip in `40k/scripts/WeaponKeywordIcons.gd` surfaces the keyword to the player
4. P0 = roster-fielded (19 tokens), P2 = catalog-only (18 tokens)

## Live-validation

Drive each of these P0 tokens live via MCP and read the dice resolution log:
- `anti-X N+` (e.g. Anti-Vehicle 3+) — confirm Critical Wound auto on N+
- `devastating wounds` — confirm mortal-wound conversion + spillover
- `lethal hits` — confirm 6 to hit auto-wounds, skip wound roll
- `sustained hits N` — confirm N additional hits on Critical Hit
- `rapid fire N` — confirm +N attacks at half range
- `blast` — confirm +1 attack per 5 models, blocked by friendlies in ER
- `melta N` — confirm +N damage at half range
- `torrent` — confirm auto-hits, no hit roll
- `precision` — allocate to attached CHARACTER
- `ignores cover` — defender doesn't get +1 cover
- `indirect fire` — -1 BS, +1 cover for target, no CHARACTER targeting
- `hazardous` — post-attack 1s test
- `twin-linked` — re-roll wound rolls
- `heavy` — +1 to hit if stationary
- `assault` — fire after Advance
- `pistol` — fire in ER, exclusive within unit when any model in ER

P2 tokens: list as table, mark as `❌ NOT APPLICABLE` (no roster invokes) without deep audit.

## Prior-audit overlap

- 2026-05 audit verified Twin-linked re-roll, Sustained Hits (Get Stuck In injection), BLAST engagement-of-friendlies block, HAZARDOUS post-attack 1s
- T7-9 weapon-keyword AI awareness (all 8 keywords); Blast formula corrected from 9e to 10e `floor(models/5)`

## Output prose

Top 5 tokens with `🐛` (divergence). Top 5 P0 tokens at depth `C/W` but not `U` (player has no idea the rule applied). Note any token applied in shooting but not melee or vice versa where Wahapedia says it should apply to both.
