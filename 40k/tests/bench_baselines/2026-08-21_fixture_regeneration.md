# PM-F3 — the 2000-point fixtures were regenerated on 2026-08-21

**Branch:** `claude/plan-maker-todo-w0syuf`
**Task:** `.llm/plan-maker-todo.md` → PM-F3

## What changed and why

The six 2000-point fixtures were built on a shell save whose `board` was
captured before the crucible zone JSON was regenerated from the 40kdc 11e
dataset. `SaveLoadManager` restores the baked board verbatim, so **every
benchmark game on the old fixtures played a stepped crucible zone (a 44x8 band
+ 24x6 centre step, obj_home_1 at (22,4)) that no menu game can produce** —
the shipped `deployment_zones/crucible_of_battle.json` is a triangle
(0,0)-(44,30)-(44,0) with obj_home_1 at (32,14).

`tests/make_2000pt_fixture.gd` now refreshes `board.deployment_zones` and
`board.objectives` from `DeploymentZoneData` + `MissionManager` after loading
the shell, packs each unit wholly inside the real zone POLYGON rather than its
bounding rectangle, and falls back to wider/narrower block shapes when the
near-square block fits nowhere (the true P2 triangle narrows to a point;
`asym_2000_postdeploy`'s Ork side failed at 45 of 77 models without this and
packs clean with it — `U_GRETCHIN_B` went out as 6 columns).

`tests/unit/test_fixture_boards_current.gd` is the rot-guard: it applies the
builder's refresh to each shipped fixture and asserts it is a fixed point, and
that every deployed model is wholly inside its own zone. It failed 12 of 24 on
the old fixtures and passes 24/24 on these.

## New sha256s (`tools/ai_lab/fixture_check.py`, all PASS)

| fixture | old | new |
|---|---|---|
| mirror_custodes_2000_predeploy | fbb7538749ec | **1e051d7d0d18** |
| mirror_orks_2000_predeploy | 140798d7ca0c | **69e30a89a221** |
| mirror_custodes_2000_postdeploy | cd9d686550a7 | **eb808b09f72d** |
| mirror_orks_2000_postdeploy | 76b7e1231601 | **faa84f0473cc** |
| asym_2000_predeploy | daefd79ea4a1 | **fc85e3eda6a5** |
| asym_2000_postdeploy | 68848d1eee18 | **16ed2ac5c80d** |

## What this does to earlier baselines

**Every report in this directory dated before 2026-08-21 that names one of the
old sha256s above was measured on the stale board and is superseded.** In
particular:

- `2026-08-11_plan_vs_formula.md` (PM-10): both arms played the stepped zone,
  and the shipped crucible plan it measured was ANCHORED to the stale
  objective at (22,4). Its adherence numbers remain internally valid (both
  arms saw the same board), but its VP effect does not transfer to the real
  triangle. The PM-F6 stall it hit is also board-specific: the stall
  reproduces on the stale board (seeds 9001/9005, deterministic, plans-OFF
  seat) and is fixed by the PM-F1 polygon guard — see the PM-F6 evidence
  block in `.llm/plan-maker-todo.md`.
- The A/A references for `mirror_custodes_2000_postdeploy` and
  `asym_2000_postdeploy` were measured on the old boards; structural-bias
  numbers (F) do not carry over and want re-measuring before the next
  campaign leans on them.

`staleboard_orks_2000_predeploy.{w40ksave,meta}` is a byte-for-byte copy of
the OLD ork predeploy fixture, kept deliberately: it is the only known
reproduction of the PM-F6 deployment stall. It is not a campaign fixture and
the rot-guard exempts it by design.
