# A/A baselines — both mirrors, 2026-08-07

**Question:** with the same AI on both sides, what margin does each mirror
fixture produce on its own? That quantity is `F` — the structural bias of the
instrument (first turn + board side) — and every A/B run on these fixtures has
to be read against it.

**Commit:** `ef5b389` (clean tree). Difficulty 2 (Hard), `BENCH_TIME_SCALE=6`,
default profile on both sides, seeds 7001–7020, three concurrent lanes via
`tools/ai_lab/run_lanes.py`. Both fixtures passed `tools/ai_lab/fixture_check.py`
before the run.

`margin = VP(P2) − VP(P1)`. Negative favours P1, who takes the first turn.

## Results (40 games)

| fixture | n | completed | **F̂** | sd | se | 95% CI | stalled |
|---|---|---|---|---|---|---|---|
| `mirror_orks_postdeploy` | 20 | 18 | **−7.11** | 11.23 | 2.65 | [−12.3, −1.9] | 2 |
| `mirror_custodes_postdeploy` | 20 | 19 | **+2.16** | 13.23 | 3.04 | [−3.8, +8.1] | 1 |

Every completed game reached battle round 5.

**The two mirrors do not share a bias, and one of them barely has one.**
The Ork mirror gives P1 roughly 7 VP for going first, distinguishable from zero.
The Custodes mirror is not distinguishable from zero at this sample size. Any
future pooling across the two matchups has to respect that; the paired
side-swapped design cancels `F` by construction, which is precisely why it is
the design to use.

## Cross-check against the previous A/A arm

`2026-08-06_mirror_new_vs_old.md` measured the Ork mirror's A/A arm at
**−3.90** (sd 15.46, se 4.89, n=10, 1 stall) on a different commit.

    difference          = −7.11 − (−3.90) = −3.21 VP
    se of difference    = sqrt(2.65² + 4.89²) = 5.56
    → 0.58 standard errors

Consistent. The harness agrees with itself across a month, a code change and a
doubling of sample size. That is the check the A/A arm exists to provide, and it
passes.

The spread also tightened as expected with the larger sample: sd 15.46 → 11.23.

## Stalls — one pattern, not three

3 of 40 games stalled (7.5%). All three are the **same signature**:

| fixture | seed | stall point |
|---|---|---|
| orks | 7012 | round 5, CHARGE phase, 733 actions |
| orks | 7017 | round 5, CHARGE phase, 711 actions |
| custodes | 7001 | round 5, CHARGE phase, 444 actions |

Round 5 charge phase, across both fixtures and unrelated seeds. This is not
three incidents; it is one defect surfacing three times, and it is the most
concrete stall lead the benchmark has produced. Full stdout for each is retained
gzipped under the season's `_logs/`.

Note the prior baseline README's claim that "the seed reproduces it
deterministically" is **not currently true** at Hard — score noise runs through
an unseeded `randf()`, so a stall found at seed N need not recur at seed N.
Seeding the AI-layer RNG (design doc M2) is what would make that claim hold.

## Throughput — the Custodes mirror is ~10× cheaper

| fixture | units/side | median actions | median wall | 20 games @ 3 lanes |
|---|---|---|---|---|
| orks | 16 | 684 | 487 s | **61.1 min** |
| custodes | 9 | 390 | 48 s | **8.5 min** |

An elite 9-unit army resolves an entire game in well under a minute, against
eight minutes for the 16-unit horde — fewer models means far less per-action
work, and roughly half the decisions.

**This changes campaign economics.** A sensitivity screen or an early racing
round can run on the Custodes mirror at nearly an order of magnitude more games
per hour, with confirmation on the Ork mirror reserved for candidates that
survive. The design document's throughput planning assumed the Ork figure for
everything.

## Reproducing

```bash
python3 tools/ai_lab/run_lanes.py --fixture mirror_orks_postdeploy \
    --seeds 7001-7020 --arm AA --lanes 3 --difficulty 2 --time-scale 6 \
    --season bench_data/season_aa_20260807
```

Per-game records, campaign summaries and failure logs land in the season
directory; `tools/ai_lab/build_index.py` turns it into a queryable DuckDB.
