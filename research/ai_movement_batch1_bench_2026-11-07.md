# AI movement intents, batch 1 — benchmark gates (2026-11-07)

Flags: `FIX_MOVE_COVER`, `FIX_MOVE_FOR_SHOT`, `FIX_MOVE_FOR_CHARGE` (all ship at 0). Method: `.llm/ai-movement-intent-guide.md` §7 (`tools/ai_lab/ai_versions.py`, `--rules11e`), run in a worktree pinned at `1b6765b` (+ the `run_lanes.py` XDG fix, `53e82bc`), 2 lanes, isolated `XDG_DATA_HOME`.

## a. OFF is a no-op

`run --base SHIP(c9b026e) --cand HEAD --fixture mirror_custodes_2000_postdeploy --seed-base 95000 --pairs 3`

| seed | margin (both seat orders) | actions |
|---|---|---|
| 95001 | −33 / −33 | 671 / 671 |
| 95002 | −8 / −8 | 727 / 727 |
| 95003 | −8 / −8 | 674 / 674 |

E = +0.00 VP, SE 0.0, CI [0.0, 0.0] — **PASS** (identical games: the three flags at 0 play exactly like the pre-batch AI).

## b. Fire gate (lines per game; below 1.0 = PARK)

Combined profile (all three ON, `HIDDEN_FORFEIT_PENALTY` 3.0, `MOVE_COVER_PLAN_WEIGHT` 0), one pair per fixture (6 games):

| flag | Custodes mirror (91000) | asym (91100) | Orks mirror (91200) | per game | verdict |
|---|---|---|---|---|---|
| FIX_MOVE_COVER | 5 | 1 | 3 | 1.50 | fires |
| FIX_MOVE_FOR_SHOT | 0 | 0 | 0 | 0.00 | — |
| FIX_MOVE_FOR_CHARGE | 2 | 3 | 1 | 1.00 | fires (at the bar) |

`FIX_MOVE_FOR_SHOT` alone (its own `move_for_shot_on.json`, same seeds, 6 games): **0 fire tags**; the stage ran 82 times and every time either no enemy was reachable within the move ("no enemy within … — straight move") or the straight move already had an eligible target ("unchanged"). Identical margins and action counts in both seat orders. Verdict: **PARK** — keep the code at 0; it is correct (exam mv06, 99 unit checks, windowed scenario) but these fixtures never produce its trigger (a move that ends with no eligible target while a target is reachable).

Not run: the directional A/B (§7c) and the V2-2 ON gate — no flag is proposed for ON.
