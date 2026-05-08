# 04.03 — Keywords

**Read first:** `00_overview.md`, `01_inventory.md`, `04_data_entities/README.md`, `universe/keywords.json`.
**Output:** `.llm/audit_2026_launch/findings/04_03_keywords.md`

## Scope

1,420 distinct keywords across all datasheets. Most are flavor (faction sub-types) and have no rule weight. The audit cares about the keywords the engine **branches on**.

### Rules-bearing keywords (canonical — verify each)

`CHARACTER`, `EPIC HERO`, `INFANTRY`, `BEAST`, `SWARM`, `MOUNTED`, `CAVALRY`, `BIKE`, `VEHICLE`, `MONSTER`, `PSYKER`, `BATTLELINE`, `FLY`, `AIRCRAFT`, `TITANIC`, `TOWERING`, `IMPERIUM`, `CHAOS`, `XENOS`, `LEADER` (ability not keyword but interacts), `LONE OPERATIVE` (ability not keyword), and faction keywords (`ADEPTUS CUSTODES`, `ORKS`, `ASTRA MILITARUM`, etc.).

For each, identify the rule(s) the engine should branch on:
- `CHARACTER` → Look Out Sir, Heroic Intervention, Leader, Precision allocation
- `EPIC HERO` → cannot have Enhancements, cannot be attached-to as second character
- `INFANTRY` / `BEAST` / `SWARM` → cover save 3+ cap, can occupy upper Ruin floors, Pile In aura
- `VEHICLE` / `MONSTER` → Big Guns Never Tire, cover save above 3+ allowed
- `FLY` → vertical movement, can move over models, can occupy upper Ruin floors
- `AIRCRAFT` → special movement (mission-pack-dependent)
- `BATTLELINE` → mission scoring rules
- `PSYKER` → various stratagems, certain enhancements bearer-restricted
- `TITANIC` / `TOWERING` → terrain LoS interactions, can't be transported
- `MOUNTED` / `CAVALRY` / `BIKE` → certain abilities key off these

For each rules-bearing keyword: find the engine code paths that branch on it. Classify per evidence model. Verify Wahapedia rule text matches implementation.

### Faction keywords (26)

For each faction in `Factions.csv`, confirm the engine recognizes its faction keyword as a unit attribute and uses it where required (army-construction validation, faction-specific ability gating).

### Flavor keywords

The remaining ~1,300+ are flavor and have no engine branch. Spot-check 20 random ones to confirm none are referenced anywhere in code (orphan check).

## Live-validation

- Big Guns Never Tire on a `VEHICLE` in ER → -1 to hit
- INFANTRY climb to upper Ruin floor → allowed; `VEHICLE` attempt → rejected
- Look Out Sir on a `CHARACTER` with non-CHARACTER ≥3-model unit closer → redirect
- Precision allocation through Look Out Sir → allowed
- Battleline scoring: place a non-Battleline unit on objective vs. Battleline → check secondary mission scoring difference

## Output prose

Top 5 keywords where the engine should branch but doesn't. Faction keywords absent from engine. Note any rule that *should* branch on a keyword but uses a hard-coded unit-name list instead (a fragile pattern).
