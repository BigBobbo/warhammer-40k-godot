# Prompt: fix `ai_shooting_stall_defender_lock` (and the test-hygiene problem behind it)

*Hand this to an LLM with repo access. The root cause below was **verified by
experiment** on 2026-08-06, not inferred — but re-verify it before acting, and
if the code contradicts this brief, the code wins.*

---

## The task

`40k/tests/scenarios/sp/ai_shooting_stall_defender_lock.json` fails **7 of 35**
assertions. Fix it properly, and fix the class of problem it exposes.

**Read this first, because it will save you from fixing the wrong thing:
there is almost certainly no bug in `ShootingPhase`. The scenario is not
hermetic.** It depends on an ambient user setting that is not part of its
fixture, and the machine it was last run on had that setting flipped.

## Root cause (verified, with the experiment that proves it)

`ShootingPhase._should_pause_for_human_saves()` (`40k/phases/ShootingPhase.gd:3029`)
returns true only if **all three** hold:

1. `GameConstants.edition >= 11` — the scenario sets this at step 2. Fine.
2. `_is_player_human(defender)` — `:2722` returns `true` whenever `AIPlayer` is
   disabled, and `ScenarioRunner` disables it. Fine.
3. `not SettingsService.get_auto_allocate_wounds()` — **this is the one.**

`auto_allocate_wounds` is a persisted user setting
(`SettingsService.gd:155`, written to `user://settings.cfg`). On the machine
where this was diagnosed it was `true`:

```
$ grep auto_allocate ~/.local/share/godot/app_userdata/40k/settings.cfg
auto_allocate_wounds=true
auto_allocate_wounds_defender_control=true
```

With it `true`, the attack never pauses — the engine auto-rolls the defender's
saves (`log: "AI saves: Boyz - 4 passed, 14 failed → 14 casualties"`),
`pending_save_data` stays empty, step 9 fails, and the remaining 6 assertions
cascade because the allocation overlay never opens.

**The proof:** flipping that one line to `auto_allocate_wounds=false` and
re-running the scenario, changing nothing else, gives:

```
[8][INFO] Boyz: 2 saves passed, 16 failed → 16 casualties (defender allocated)
[ScenarioRunner] === ai_shooting_stall_defender_lock: 35 passed, 0 failed ===
```

35/35. The setting was restored to `true` afterwards, so the failure is still
reproducible as described.

**Corollary:** this is *not* a regression from any recent branch. The scenario
fails identically at merge-base `5eb5141` and on current `main`, because both
runs read the same `settings.cfg`.

## What to actually fix

Decide between these and justify the choice — do not just do the first one:

1. **Make the scenario hermetic.** Have it assert or set the setting it depends
   on. Note `40k/tests/scenarios/_schema.md` already documents an
   `execute_script` act, and `ScenarioRunner` already exposes a
   `SettingsService.set_unit_color_display_mode` helper at
   `autoloads/ScenarioRunner.gd:1887` — so there is precedent for a scenario
   driving settings.
2. **Make the runner hermetic.** Have `ScenarioRunner` reset the settings that
   affect game logic to known defaults before every scenario, and restore
   afterwards. Stronger, but touches every scenario — assess blast radius.
3. **Both**, if a scenario needs a *non-default* setting.

Whatever you choose, the property you are buying is: **a scenario's result must
not depend on the machine it runs on.** State how your fix guarantees that.

## The wider problem — this is the real deliverable

There are **478** scenarios under `40k/tests/scenarios/sp/`. At least one of
them silently depended on ambient user config, and nobody noticed because it
fails the same way for everyone whose settings happen to differ.

Audit for the same class of bug:
- Which `SettingsService` values change game *logic* (not just presentation)?
  `auto_allocate_wounds` is one; find the others.
- Which scenarios depend on one without setting it?
- Is there a cheap guard — e.g. the runner logging every logic-affecting
  setting it started with, so a failure report is self-diagnosing?

## A real inconsistency found while diagnosing — fix or explain

The three call sites disagree about what a **missing** `SettingsService` means:

| site | expression | fallback when `ss == null` |
|---|---|---|
| `ShootingPhase.gd:3035` | `ss != null and ss.get_auto_allocate_wounds()` | **do not** auto-allocate |
| `FightPhase.gd:1257` | `_ss == null or _ss.get_auto_allocate_wounds()` | **do** auto-allocate |
| `FightPhase.gd:1494` | `ss == null or ss.get_auto_allocate_wounds()` | **do** auto-allocate |

Shooting and Fight take opposite defaults for the same missing service. One of
them is wrong. Work out which, fix it, and say why — or, if both are
deliberate, document the reason at each site.

## An open question you must NOT assume away

The `Windowed Scenario Suite` workflow has been **red on `main`** since at
least 2026-08-05 (four consecutive completed runs failed;
`Automated Test Suite` passes).

**Do not assume this scenario is the cause.** CI runners start with a fresh
`user://`, where `auto_allocate_wounds` defaults to `false`
(`SettingsService.gd:155`) — so on CI this scenario should *pass*. That means
the suite is very likely red for a **different** reason.

So: fix this scenario, then separately determine what is actually failing on
CI, from the CI logs rather than from local runs. Report them as two findings.
If fixing this one happens to turn CI green, prove it rather than infer it.

## How to run things

```bash
export PATH="$HOME/bin:$PATH"

# the failing scenario alone
bash 40k/tests/run_scenario.sh tests/scenarios/sp/ai_shooting_stall_defender_lock.json

# the whole single-player suite (what CI runs; slow)
bash 40k/tests/run_scenarios.sh --sp

# only scenarios whose 'covers' tags overlap files changed vs main
bash 40k/tests/run_scenarios.sh --changed-only
```

Exit 0 = all assertions passed. Failures auto-capture a screenshot to
`user://test_results/scenarios/<id>_FAIL_step_<n>.png`.

The game runs windowed in a headless container — the `godot` shim wraps it in
`xvfb-run` with software rendering. See `CLAUDE.md`; do not report that you
cannot run the game without trying.

## What the scenario is protecting (do not weaken it)

From its own description: a real reported bug (2026-08-03) where the AI's
shooting phase froze after a human defender took time over saves. While an
attack is paused on save allocation the phase used to keep offering
`RESOLVE_SHOOTING` / `SELECT_SHOOTER` / `SKIP_UNIT`, so a stray click or AI
evaluation re-entered the paused activation, re-rolled the whole attack behind
the defender's back, and deadlocked the phase.

The scenario asserts the **defender control lock**: only `APPLY_SAVES` on
offer, every re-entry action rejected, `END_SHOOTING` deliberately left
unlocked as the player's manual escape hatch, then walks the real allocation
overlay to Done and checks the batch drained.

**That coverage is valuable. Do not make the test pass by deleting assertions,
loosening them, or skipping the pause path.** If you believe an assertion is
genuinely wrong, argue it explicitly.

## Rules of engagement

- Verify the root cause yourself before acting; cite `file:line`.
- Distinguish what you ran from what you reasoned about.
- Per `CLAUDE.md`, a fix to player-facing behaviour needs a windowed scenario
  proving it. A fix to test hygiene needs the scenario passing **and** evidence
  it now passes regardless of ambient settings — demonstrate it under both
  values of the setting.
- Do not change `AIDecisionMaker` behavioural constants; unrelated, and they
  ship neutral deliberately (`tests/bench_baselines/2026-08-06_mirror_new_vs_old.md`).

## Non-goals

- Do not "fix" `_should_pause_for_human_saves` to ignore the setting — the
  setting is a real player preference and honouring it is correct.
- Do not delete or `skip` the scenario.
- Do not tune the AI.
