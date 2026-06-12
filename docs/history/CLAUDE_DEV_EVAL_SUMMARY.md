# Claude dev evaluation — visual-regression loop

**Author:** Claude (cloud session)
**Date:** 2026-05-19
**Audience:** Senior engineer review
**Status:** Infrastructure complete + validated against full scenario library; 3 pre-existing scenario bugs surfaced + fixed.

---

## TL;DR

Built an automated "run windowed scenario → diff against visual golden → critic agent triages failure → fixer agent proposes patch" loop, in 7 incremental phases on stacked branches. Validated it against all 25 scenarios via a 35-iteration sweep that found and fixed 5 real infrastructure bugs and surfaced 3 pre-existing scenario reds (now fixed on a separate branch).

The loop's **mechanics are validated**. What is **not yet validated** is the end-to-end fixer→merge automation against a real regression — only against synthetic ones. That gap is intentional and called out in the playbook; closing it needs a real UI-changing PR to test against.

---

## What I was asked to do

Build infrastructure that lets a Claude cloud session detect UI regressions automatically:

1. Run a Godot scenario windowed under xvfb
2. Capture a screenshot after every step (not just on failure)
3. Diff each screenshot against a blessed "golden" reference image
4. When something drifts, hand the manifest + screenshots to a critic agent for triage
5. When triage decides "real regression," hand it to a fixer agent that proposes a patch and re-runs the loop
6. Make all of this safe enough to run unattended

---

## What I built (by branch)

All branches are stacked off `main` and pushed to `origin`.

| Branch | What it adds | Why it matters |
|---|---|---|
| `claude/visual-regression-loop` (Phase 1) | `ScenarioRunner` `SCENARIO_SCREENSHOT_EVERY_STEP=1` mode + per-step PNGs + driver script + **stub critic** | Smallest end-to-end vertical slice. Proves the I/O contract works before adding any intelligence. |
| `claude/visual-regression-loop-phase2` | `golden_diff.py` (PHASH @ 64-bit, per-scenario thresholds in `_thresholds.json`) | Turns "did the run finish" into "did the UI drift." This is the actual regression net. |
| `claude/visual-regression-loop-phase3` | `SCENARIO_SELECTOR_DRY_RUN=1` preflight + `determinism_check.sh` (same seed → same PHASH) | Two cheap gates that fail fast *before* spending an expensive windowed run on a scenario whose selectors won't resolve or whose output is non-deterministic. |
| `claude/visual-regression-loop-phase5` | Real **critic Agent** (Claude subagent, returns structured JSON) + `playbook.md` + live demo evidence | Replaces the stub. The critic now actually reads screenshots and triages. Skipped phase 4 — was merged into phase 5 because the stub→real swap was a single landable unit. |
| `claude/visual-regression-loop-phase6` | `.githooks/pre-commit-loop` — scenarios immutable, fixer can't edit the test it's trying to pass, no megadiffs, mandatory Justification paragraph | Mechanical guardrails. The fixer is a Claude Agent; this hook is what prevents a creative fixer from making a red test green by editing the test. Fires only on `loop/*` branches; no-op everywhere else. |
| `claude/visual-regression-loop-phase7` | Parallel kickoff script, priority sorter, **35-iteration sweep against all 25 scenarios**, 5 infrastructure bugs fixed (each surfaced by a real iteration) | Validates the loop's mechanics against the full scenario library, not just `runner_smoke`. |
| `claude/fix-scenario-reds` (follow-up off main) | Fixes the 3 pre-existing scenario reds the sweep surfaced | These were blocking `--bless` on those 3 scenarios. Each was a distinct, real bug — details below. |

---

## What works today (feasible, validated)

- **Per-step screenshot capture** — `SCENARIO_SCREENSHOT_EVERY_STEP=1` produces `<id>_step_NN_<act>.png` for every step.
- **Golden PHASH diff** — drift detected at 64-bit perceptual hash with per-scenario thresholds (most are 6-bit Hamming distance, can be tuned).
- **`--bless` workflow** — operator-driven baseline update. **Refuses to bless** if the scenario itself failed (Phase 7 fix — prevented baseline corruption on the 3 pre-existing reds).
- **Selector preflight** — `SCENARIO_SELECTOR_DRY_RUN=1` walks the scenario, resolves `click_node` / `click_unit` / `expect_node_*` / `expect_token_visible` selectors, writes a report. Phase 7 fix: skips preflight when the scenario has no selectable steps (saved ~15s × N scenarios).
- **Determinism check** — same seed twice; PHASH must match. Catches scenarios that look passing but flake under iteration.
- **Real critic Agent** — reads manifest + per-step screenshots, returns structured `{verdict, reason, suggested_action}` JSON. Lives in `scripts/loop/critic_prompt.md`.
- **Pre-commit-loop guardrails** — six mechanical checks (immutable scenarios, no megadiff, no `save_load.gd`, mandatory justification, scoped paths, no `--no-verify`). Fires only on `loop/*` branches.
- **Sweep tooling** — `list_scenarios_by_priority.py` orders the queue by coverage tile age + risk; `kickoff_parallel.md` documents the multi-session fan-out.
- **All 22 previously-passing scenarios still pass** after the infrastructure changes (regression-checked).
- **All 25 scenarios can now bless cleanly** after the `fix-scenario-reds` branch lands.

---

## What's not feasible / not done yet

- **End-to-end fixer→merge automation against a real regression** — only tested against synthetic drift (intentionally-broken UI commits I introduced and reverted). No real-world regression has flowed through critic → fixer → green PR yet. Closing this needs a real UI-changing PR landing while the loop is watching.
- **Critic accuracy on subtle regressions** — the critic agent reliably catches gross drift (layout breaks, missing tokens) but I haven't measured its false-positive/false-negative rate on subtle regressions (e.g. one-pixel anti-aliasing change, font hinting differences). Needs a labeled corpus to benchmark.
- **Cross-scenario coverage of the orphan tags** — `check_coverage.py` reports ~30 scenarios declaring `covers` tags that don't exist in `coverage.json`. These predate my work. My commit added the 4 tiles for the scenarios *I* touched. The remaining ~26 each need a hand-written feature description that the loop can't synthesise — needs human or product input.
- **Parallel scenario execution** — the kickoff script documents fan-out across multiple cloud sessions, but I haven't load-tested whether N parallel sessions interfere via shared `user://` paths. Single-session sweeps are confirmed safe.
- **Real Godot install on cloud runners** — the SessionStart hook installs Godot 4.4.1 + xvfb each session. Cold-start is ~40s. Acceptable for one-shot runs; would want a pre-built image for high-frequency loops.

---

## The 3 pre-existing scenario reds (surfaced by Phase 7, fixed on `claude/fix-scenario-reds`)

Each was a real, distinct bug — not a flake.

| Scenario | Root cause | Fix |
|---|---|---|
| `372_ere_we_go_charge_modifier` | Fixture saves with player 2 active and `player2_type=AI`. The AI raced through player 2's charge turn during the scenario's first `wait_seconds`, marked `U_BOYZ_E` as completed, and rejected the scenario's `DECLARE_CHARGE` with `success=false`. | Added optional `disable_ai: true` scenario field. Runner sets `AIPlayer.enabled=false` when set. Defaults off — preserves AI for scenarios that intentionally test it. **8/8 ✓** |
| `373_lone_operative_guard` | Scenario was **wrong**, not the engine. It expected Lone Operative characters to be **rejected** from attaching to a bodyguard. 10th-edition rules (and an explicit comment in `FormationsPhase.gd:197-199`) say LO is a *targeting restriction*, not an attachment ban. The engine was correctly updated for 10e; the scenario was never updated. | Flipped expectations: LO Blade Champion now expected to attach successfully, undeclares cleanly, Shield Captain (non-LO) attaches afterwards. **11/11 ✓** |
| `fight_self_targeting` | Scenario waited 1s and *then* asserted `phase=10`. But this scenario *wants* AI behaviour preserved (it tests "does AI self-target?"). The AI raced through fight + scoring + start-of-next-turn during the wait, leaving the engine in phase 6 by the assertion. | Reordered: phase=10 assertion fires immediately after `transition_to_phase`, then waits for AI. Description updated to clarify the scenario is observational — goldens are the deliverable. **4/4 ✓** |

These are good examples of what the loop is *meant* to surface: bugs that headless tests can't catch because they only fail when the full UI + AI + phase-manager pipeline runs end-to-end.

---

## How to verify the work

```bash
# 1. Run the loop driver against a single scenario
bash scripts/loop/run_one_scenario_loop.sh tests/scenarios/sp/runner_smoke.json

# 2. Run the loop with bless (creates goldens on first pass)
bash scripts/loop/run_one_scenario_loop.sh --bless tests/scenarios/sp/runner_smoke.json

# 3. Run a single scenario directly (no loop wrapper)
xvfb-run -a godot --path 40k --scenario-file=tests/scenarios/sp/372_ere_we_go_charge_modifier.json

# 4. Confirm the 3 reds are fixed (after merging claude/fix-scenario-reds)
for s in 372_ere_we_go_charge_modifier 373_lone_operative_guard fight_self_targeting; do
  xvfb-run -a godot --path 40k --scenario-file=tests/scenarios/sp/${s}.json 2>&1 | grep "==="
done

# 5. See the critic prompt
cat scripts/loop/critic_prompt.md

# 6. See the per-iteration playbook
cat scripts/loop/playbook.md
```

---

## Files of interest for a deep-dive review

| File | What's in it |
|---|---|
| `.llm/visual-regression-loop-plan.md` | Original design doc that the 7 phases implement |
| `40k/autoloads/ScenarioRunner.gd` | Per-step screenshot mode, selector dry-run mode, `disable_ai` handling |
| `scripts/loop/run_one_scenario_loop.sh` | Per-scenario driver — the canonical entry point |
| `scripts/loop/golden_diff.py` | PHASH diff implementation + threshold handling |
| `scripts/loop/critic_prompt.md` | The Claude Agent prompt for the critic |
| `scripts/loop/fixer_prompt.md` | The Claude Agent prompt for the fixer |
| `scripts/loop/playbook.md` | Runbook for the cloud session driving one iteration |
| `.githooks/pre-commit-loop` | Mechanical guardrails on fixer-authored commits |
| `40k/tests/scenarios/_schema.md` | Scenario JSON schema |
| `40k/tests/TESTING_METHODOLOGY.md` | Project's windowed-scenario doctrine |

---

## What I'd want the senior engineer to evaluate

1. **Is the critic prompt's verdict taxonomy good enough?** Currently: `real_regression` / `intentional_change_needs_bless` / `flake_rerun` / `scenario_bug`. Are these the right buckets? Is the JSON schema usable?
2. **Are the pre-commit-loop guardrails the right set?** Specifically, the "scenarios immutable" rule means a fixer can never propose a scenario change even when the scenario IS the bug (as in 373). Is the right answer to relax that, or to require human-in-the-loop for scenario edits?
3. **Is the per-step screenshot strategy too expensive?** ~10-30 PNGs per scenario. Storage is fine but goldens-as-source-of-truth means baseline drift on font/theme changes touches every scenario at once.
4. **Should the loop run on every PR or only nightly?** Cold-start + 25 scenarios × 30s ≈ 12min per full sweep. Per-PR is feasible if scoped to scenarios touching changed code paths; full sweep belongs in nightly.
5. **The orphan coverage tiles** — should I have blocked on fixing those (~26 tiles) before declaring infrastructure complete, or is the current "block only on tiles you touch" gate the right tradeoff?
