# B2 — `asym_orks_vs_custodes_postdeploy`: the fixture and its bias

**Date:** 2026-08-07 · **Fixture sha256:** `784fc01f1e1c` · **Built by:**
`40k/tests/make_asym_fixture.py`

## Why a third fixture

The two mirrors do a job nothing else can: they remove the army asymmetry *by
construction*, so a paired A/B isolates the candidate and nothing else. What
they cannot do is detect **matchup overfitting**. A change that helps Orks
fight Orks may lose to Custodes, and a mirror will never say so — both sides
get the change, so a bias that only shows against a different army is
invisible by construction. `gate_candidate.py` already asks for a ≥2-matchup
grid; before this it could only be given two views of the same matchup.

## What it is

| | P1 | P2 |
|---|---|---|
| Faction | Adeptus Custodes (Lions of the Emperor) | Orks (Speedwaaagh!) |
| Units | 9 | 16 |
| Points | 1335 | 1840 |
| Reserves | 0 | 0 |
| Start | round 1, phase 6 (Command), P1 first turn | |

Built by splicing, not by hand: take the Custodes mirror, delete P2's mirrored
Custodes, paste in the Ork army from the Ork mirror's P2 side. Both mirrors
descend from the same source save, so the board, terrain, objectives and
deployment zones are identical and the Ork models are already deployed in the
P2 half. **Nothing is repositioned**, so neither army's deployment is
second-guessed by the script.

The armies are deliberately **not** equal on points. That is the shipped
matchup; equalising it would invent a list no player fields, and the whole
point of the fixture is to be a different *kind* of test from the mirrors.

```
$ python3 tools/ai_lab/fixture_check.py asym_orks_vs_custodes_postdeploy
[PASS] asym_orks_vs_custodes_postdeploy
   P1: 9 units, 1335 pts, 0 pts (0%) in reserve
   P2: 16 units, 1840 pts, 0 pts (0%) in reserve
   round=1 phase=6 active=P1 first_turn=P1  sha256=784fc01f1e1c
```

## A/A reference — the structural bias F

Same AI, shipped defaults, both sides. Hard (difficulty 2), 20 games,
seeds 7001-7020.

```
python3 tools/ai_lab/run_lanes.py --fixture asym_orks_vs_custodes_postdeploy \
    --seeds 7001-7020 --arm AA --lanes 2 --season <season>
```

| | value |
|---|---|
| games | 20 (20 completed, **0 stalled, 0 timed out**) |
| F (mean margin P2−P1) | **−11.30 VP/game** |
| sd | 11.34 |
| se | 2.54 |
| 95% CI | [−16.27, −6.33] |

**Sign and magnitude.** F is negative and clearly non-zero: **P1 (Custodes)
wins by about 11 VP despite fielding 505 fewer points.** Two effects push the
same way — P1 takes the first turn on this fixture (worth ~19 VP at Hard on
this board per `2026-07-10_firstturn_swap.md`), and nine elite bodies with
2+/4++ saves and OC 2-5 are simply better at holding five objectives than
sixteen Ork bodies are at taking them from them. The points gap partially
offsets the first-turn advantage rather than reversing it.

**This is not a problem, and it must not be "fixed".** `run_paired.py`
side-swaps every seed, so F cancels exactly and the reported effect E is free
of it. A large, *known*, *stable* F is fine; an unknown one is not. What would
be a problem is F drifting between campaigns, which is why it is written down
here with its interval.

**Spread.** sd 11.34 is at the low end of the 9-15 VP per-seed range the
mirrors show, so this fixture is no noisier to evaluate on than they are:
roughly the same games-per-VP-of-resolution.

## How to use it

Third arm in a gate grid, never on its own:

```
python3 tools/ai_lab/run_paired.py --candidate cand.json \
    --fixture asym_orks_vs_custodes_postdeploy --season <season>
```

A candidate that wins on both mirrors and loses here has not been shown to be
better — it has been shown to be *matchup-specific*, which is exactly the
failure mode this fixture exists to expose.
