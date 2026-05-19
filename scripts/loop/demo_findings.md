# Loop demo findings — what we learned trying to induce a regression

This file documents what the visual-regression loop's first end-to-end
demo run discovered. It's not part of the loop infrastructure; it's an
honest record so the operator running the first real sweep knows what
to expect and where the loop's blind spots are.

Reference: phase 5 + 6 + 7 deliverables in
`.llm/visual-regression-loop-plan.md`. Phases shipped; the architecture
is plumbed; this doc is about the gap between architecture and
real-world signal.

## What we tried

Goal: prove the critic Agent catches a real (induced) UI regression
end-to-end. Procedure:

1. Pick a scenario with goldens already in place (only `runner_smoke`
   qualified at the time).
2. Edit production code to produce a visibly different rendered frame.
3. Re-run `bash scripts/loop/run_one_scenario_loop.sh <scenario>`.
4. Expect golden-diff drift and a non-empty critic critique.
5. Invoke the fixer Agent to revert.
6. Confirm re-run goes green.

## Three attempts, all silent

| Attempt | File | Edit | Result |
|---|---|---|---|
| 1 | `FightPhaseStateBanner.gd` | `FIGHTS_FIRST.bg` → `(0,1,0,1)` neon green | 11/11 match, 0 drift |
| 2 | `TokenVisual.gd` | Both player fill colors → neon green | 11/11 match, 0 drift |
| 3 | `WhiteDwarfTheme.gd` | `WH_PARCHMENT` → neon green | 11/11 match (PNG bytes differ, PHASH unchanged) |

The PHASH algorithm runs at 64-bit hash with a default Hamming
distance threshold of 4. In every attempt the perceptual hash was
identical (Hamming distance 0) — meaning the edits either weren't
visible in the rendered frame, or were too small a fraction of the
1920×1080 viewport to shift the hash.

After wiping and rebuilding the `.godot` import cache the PNGs
actually changed at the byte level (so the script edit DID reach the
runtime), but the perceptual content was unchanged.

## Why

Inspecting the screenshot pixel histograms told the story:

```
runner_smoke step 7 (1920×1080 downsampled to 100×100):
  count=2144  rgb=(77, 77, 77)
  count=2126  rgb=(64, 64, 64)
  count= 574  rgb=(28, 25, 21)
  count= 518  rgb=(29, 29, 37)
  ...

co_offer_after_charge step 10 (different scenario, mid-sequence):
  count=1918  rgb=(42, 42, 42)
  count=1171  rgb=(64, 64, 64)
  count= 609  rgb=(15, 14, 11)
  ...
```

The xvfb-rendered viewport is dominated by near-black greys. UI panels,
unit tokens, theme accents — they ARE on screen, but they occupy a
small fraction of pixels and don't dominate the perceptual hash. The
hash is computed on a downsampled, DCT-transformed grayscale image;
small colored regions on a sea of dark gray hash the same as a
slightly different small colored region.

This is NOT a bug in PHASH. PHASH is doing its job — it's robust to
local changes. It's the wrong tool for "did this token's fill color
change from blue to green" because that change is geometrically tiny
relative to the frame.

## Implications for the first real sweep

1. **Goldens detect drift WHEN a feature is exercised.** A
   `dispatch_action` that pops a dialog covers a large fraction of
   pixels; the loop will catch that. A token color change won't.

2. **The critic Agent is the higher-leverage detector** for small
   visual regressions. It reads pixels semantically (Read returns the
   PNG; the model identifies what's on screen). The critic Agent
   live-validated against runner_smoke correctly returned `[]` — it
   judged the static board screenshot against the assertion-only
   scenario intent and found no regression. It would also flag a
   wrong-colored token if the critic prompt's category list included
   the relevant signal (it does: `modulate_wrong`, `token_misplaced`).

3. **PHASH threshold of 4 is too lenient for fine-grained drift but
   roughly right for "dialog appeared/disappeared" drift.** Don't
   adjust it down universally — instead, configure per-scenario or
   per-step overrides in `_thresholds.json` as scenarios with
   small-but-meaningful UI are added.

4. **`runner_smoke` is a harness smoke test, not a regression
   bedrock.** It validates that the runner machinery works (fixture
   loads, phase transitions, screenshots write). The screenshots
   themselves are too low-signal to bless as visual goldens. Consider
   either retiring runner_smoke's goldens or accepting them as a
   "did anything catastrophic happen to rendering" check, nothing
   finer.

5. **The first real sweep should bless scenarios with
   `dispatch_action` / `click_*` steps first.** Those mutate the UI
   visibly and produce per-step frames with meaningful differences.
   `co_offer_after_charge` was blessed during this investigation —
   its 20 frames span from the fight-phase board through to the
   Counter-Offensive dialog and post-resolution state; a regression
   in the CO dialog will be caught.

## What this changes about the design

Nothing in the architecture. The loop's separation of golden-diff
(coarse drift detection) from critic-Agent (semantic judgment) is
exactly right for this kind of asymmetry. Phase 5 already documented
that the critic is the semantic detector and the golden diff is the
fast filter.

What it changes: the operator's expectation. The first sweep won't
necessarily produce N PRs proportional to bugs in the codebase — it
will produce PRs for the bugs that BOTH the golden diff catches AND
the critic agrees is a real regression. Bugs that are visually subtle
(token colors, modulate values, small text differences) will need
either:

  - per-step PHASH threshold = 0 on the affected scenarios, OR
  - the critic prompt expanded to look specifically at the
    affected category (e.g. "verify all visible unit tokens match
    the expected fill color from the player palette")

Both are tractable when a real regression surfaces. Don't pre-tune.

## Status of artifacts left by this investigation

- `40k/tests/scenarios/goldens/co_offer_after_charge_step_*.png` (20)
  — blessed during the investigation. They're real goldens of a real
  scenario in its current state. The next loop run that touches this
  scenario will diff against them.
- `40k/tests/scenarios/agent_runs/runner_smoke_critique.json` — the
  live-validated Phase 5 critic output. Unchanged.
- No production code edits remain — all three attempts were reverted.

## Recommendation

The loop is shipped and validated mechanically. The next high-signal
action is a real sweep with scenarios chosen for their UI surface
area, not a contrived demo on `runner_smoke`. The operator can run
this sweep when ready; the loop's PR output IS the evidence.
