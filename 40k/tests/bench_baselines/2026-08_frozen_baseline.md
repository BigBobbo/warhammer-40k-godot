# B0 — the frozen 2026-08 baseline

**Frozen at:** `333f23f` (2026-08-07, after A1-A5 landed) ·
**Profile:** `40k/data/ai_profiles/baseline_2026_08.json` ·
**Tag:** `ai-baseline-2026-08` (local; pushing tags is refused by this
environment's git proxy — `send-pack: unexpected disconnect`. The freeze is
identified by the sha above and by `frozen_at.git_sha` inside the profile, so
nothing depends on the tag reaching the remote.)

## What this is for

Every comparison in this repo has been candidate-vs-current. That is a moving
target. A change measured at +2 VP against a version that had itself drifted
tells you nothing about whether the AI is better than it was in August, and it
makes the question "is the AI improving?" unanswerable in principle.

This freezes the opponent. `baseline_2026_08.json` lists an **explicit value
for every parameter in the manifest** (238 of them), not just the ones anyone
has tuned. That matters twice over:

* A later change to a `const` default cannot move the baseline underneath a
  comparison. The freeze means what it says.
* It sidesteps the silent-zero trap by construction. `_get_base_param_value`
  returns `0.0` for any parameter the profile does not declare, so a
  `multiply` on an undeclared parameter turns the weight **off** rather than
  scaling it (`tools/ai_lab/README.md`, trap 1). A profile that declares all
  238 has nothing left to zero.

## Measuring against it

```
python3 tools/ai_lab/vs_baseline.py --candidate cand.json --season <season>
python3 tools/ai_lab/vs_baseline.py --candidate cand.json --season <season> \
    --fixture mirror_orks_postdeploy --min-pairs 8 --max-pairs 24
python3 tools/ai_lab/vs_baseline.py --selftest        # frozen vs frozen
```

`vs_baseline.py` is a thin, deliberate wrapper over `run_paired.py` — same
side-swapped pairing, same pre-registered stopping rule, same statistics. The
only thing it adds is that the baseline arm is pinned to a *file* instead of
to "whatever the defaults are today", and that the report names the freeze.

### Self-test: frozen vs frozen must be exactly zero

```
python3 tools/ai_lab/vs_baseline.py --selftest --season <season> --lanes 1
  VERDICT: NO_OP   after 3 pair(s) = 6 games
  E = +0.00 VP/game   se 0.00   95% CI [0.00, 0.00]
  SELFTEST: frozen vs frozen  E = +0.00  se = 0.00  ->  PASS
```

A frozen profile played against itself has to be a no-op. A non-zero effect
would mean either that the profile is not pinning the values it claims to, or
that the pairing is not sharing random numbers — and either would invalidate
every number measured against it.

## Reference A/A numbers

Baseline profile on **both** sides, Hard (difficulty 2), shipped fixtures. The
mean margin here is F, the fixture's structural bias (first turn plus board
side) and nothing else; `run_paired` cancels it by side-swapping.

| Fixture | games | completed | stalled | F (P2−P1) | sd | se | 95% CI |
|---|---|---|---|---|---|---|---|
| `mirror_custodes_postdeploy` | 20 | 20 | 0 | **−0.25** | 11.96 | 2.67 | [−5.49, +4.99] |
| `mirror_orks_postdeploy` | 10 | 10 | 0 | **−6.20** | 7.64 | 2.42 | [−10.90, −1.50] |
| `asym_orks_vs_custodes_postdeploy` | 20 | 20 | 0 | **−11.30** | 11.34 | 2.54 | [−16.27, −6.33] |

The Custodes mirror's F is indistinguishable from zero (CI straddles it
comfortably), which is what a mirror *should* look like once first-turn
advantage is the only asymmetry and the board is rotationally symmetric. The
asymmetric fixture's F is large and known — see
`2026-08_asym_fixture_AA.md` for why, and why that is fine.

All three fixtures completed every game with **zero stalls and zero
timeouts**, which is itself the stall-rate reference future soaks are read
against.

The Custodes mirror's F is indistinguishable from zero, which is what a mirror
*should* look like once first-turn advantage is the only asymmetry and the
board is rotationally symmetric. The Ork mirror's F is −6.20 ± 2.42 — small,
negative, and marginally distinguishable from zero (the 95% interval clears it
by 1.5 VP). It is the same board and the same rotation, so the residual is the
first-turn advantage failing to cancel: sixteen Ork bodies converting a first
move into board control is worth more than nine elite bodies doing the same,
which is the asymmetry a mirror cannot remove. Ork spread is also visibly
tighter (sd 7.64 against the Custodes mirror's 11.96), so the Ork mirror
resolves a given effect in fewer games than its cost-per-game suggests — worth
knowing, given it is 10x the wall clock.

## When to re-freeze

**Rarely, and never quietly.** Re-freeze only at a genuine milestone — a
shipped profile that cleared `gate_candidate.py`, or a structural change that
makes the old baseline unrepresentative of anything anyone would play.

**Keep every old freeze forever.** The ladder is the entire point: margin
against `baseline_2026_08` rising release over release is absolute progress,
and that statement evaporates the moment a freeze is deleted or edited in
place. A new freeze is a new file (`baseline_2026_12.json`), a new tag, and a
new row here — never an edit to this one.

A re-freeze must land with:
1. the new profile, regenerated from the manifest so it is complete;
2. `validate_profile.py` passing on it;
3. `vs_baseline.py --selftest` passing against it;
4. its own A/A table, measured, not inherited;
5. one paired run of the **new** freeze against the **old** one, so the step
   between them is a number rather than an assumption.
