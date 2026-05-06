# Session playbook — feature work + scaled validation

This is the rules of the road for any Claude session that touches gameplay
code. The goal is structural: prevent the failure mode where a session
claims a feature is verified but the player can't actually use it. See
`CLAUDE.md` for the project's binding feature-validation rule.

## One-time setup (per clone)

```bash
git config core.hooksPath .githooks
```

This activates `.githooks/pre-commit` so commits with broken UI wires fail
locally before they hit CI. The hook is skipped automatically when no
gameplay files are staged. Override for emergency commits:

```bash
SCENARIO_PRECOMMIT=skip git commit -m "..."
```

## Daily session loop

### 1. Pick the work

- A reported bug → existing tile in `40k/tests/coverage.json` likely
  applies; identify it, plan to either tighten the existing scenario or
  add a new one
- A new feature → identify the cover tag (`<phase>.<concept>.<detail>`),
  check if a tile already exists in `coverage.json`; add a new tile if
  not
- A pure-math / pure-state change with no UI → headless GDScript test
  is sufficient; no scenario required

### 2. Write the scenario FIRST (red phase)

Author `40k/tests/scenarios/sp/<id>.json` (or `mp/<id>.json` for
multi-peer). The schema is documented at
`40k/tests/scenarios/_schema.md`. Minimum quality bar:

- Every player-facing action goes through `click_unit` / `click_node` /
  `simulate_key` — NEVER `dispatch_action`. `dispatch_action` is
  permitted only for setup steps that have no UI affordance (e.g.
  `END_MOVEMENT` from a phase that auto-advances, or seed-from-context
  setup).
- Visual checkpoints at minimum: one screenshot after fixture load, one
  after the trigger fires, one after the player resolves it.
- Token / dialog visibility asserts before the relevant click step
  (`expect_token_visible`, `expect_node_visible`).
- State asserts using the canonical phase-instance fields where
  available (`expect_phase_property`) rather than guessed flags.
- An RNG seed if any dice roll is involved.

Run the scenario:

```bash
bash 40k/tests/run_scenario.sh tests/scenarios/sp/<id>.json
```

It SHOULD fail at this point — that proves the asserts are tight. If
the scenario goes green before the implementation, the asserts are not
asking enough of the system.

### 3. Implement until green

Iterate on the implementation. After each change:

```bash
bash 40k/tests/run_scenario.sh tests/scenarios/sp/<id>.json
```

The runner saves screenshots at every `screenshot` beat AND auto-captures
a screenshot on the first failed step. Inspect them in
`~/Library/Application Support/Godot/app_userdata/40k/test_results/scenarios/`
(macOS) or `~/.local/share/godot/app_userdata/40k/test_results/scenarios/`
(Linux).

### 4. Update coverage.json

When the scenario passes, add or update its tile:

```json
{
  "id": "<phase>.<concept>.<detail>",
  "description": "...",
  "scenarios": ["<scenario_id>"],
  "last_verified_commit": "HEAD",
  "status": "covered"
}
```

Set `last_verified_commit` to the SHA you're about to commit. Run the
coverage check:

```bash
python3 40k/tests/check_coverage.py
```

It enforces: every covered tile references an existing scenario file,
every scenario's cover tags map to a tile.

### 5. Commit

```bash
git add 40k/<changed_files> 40k/tests/scenarios/sp/<id>.json 40k/tests/coverage.json
git commit -m "..."
```

Pre-commit hook re-runs the headless audit suite + matching scenarios.
On green, the commit lands.

### 6. Push (when authorized)

CI runs the full suite under Xvfb. Linux rendering sidesteps the macOS
backgrounded-window stale-frame issue. Screenshots and results are
uploaded as artifacts even on failure.

---

## Hard rules (the over-claim killer)

| Rule | Why |
|------|-----|
| **No "verified" claim without a passing scenario file.** Past sessions have closed features as verified using `dispatch_action`-only evidence; the player UI was actually broken and the bug shipped. | Documented failures: COUNTER-OFFENSIVE / HEROIC INTERVENTION / RAPID INGRESS rendering, stratagem PR #350 over-claim |
| **`dispatch_action` is for setup steps only.** Player-triggered actions MUST go through `click_unit` / `click_node`. | `dispatch_action` validates the engine accepted the action; it does NOT validate the player can reach it |
| **The headless audit suite is necessary but not sufficient.** A change is not done when `run_pretrigger_tests.sh` is green; it's done when the matching scenario is also green. | Headless tests bypass the rendering and signal pipelines; many UI bugs only surface in windowed mode |
| **An incomplete scenario is honest.** If you can't fully validate the player path because the UI doesn't expose the action yet, write the scenario, mark its tile `status: "scaffolded"`, and surface the gap explicitly. Do NOT fall back to dispatch_action and call it done. | Scaffolding tracks known gaps; `dispatch_action` fallbacks hide them |

---

## Anti-patterns

- Writing the scenario AFTER the implementation. Almost always produces
  asserts that pass for the wrong reason.
- Asserting only the action's return value without a follow-up state
  assert. Phase actions sometimes return `success: true` while the
  state diff fails to apply.
- Catching test errors with `try/except`-style suppression. Failures
  should be loud. The runner does not silently advance past failed
  steps.
- One mega-scenario that covers everything. If a scenario has more than
  ~30 steps it should be split. Failure isolation matters.
- Adding tile entries to `coverage.json` with `status: "covered"` and
  no scenario reference. `check_coverage.py` will reject this; don't
  fight the validator.

---

## Quick reference

| Tool | Purpose |
|---|---|
| `bash 40k/tests/run_pretrigger_tests.sh` | Headless audit suite (~2 min, ~475 asserts). Fast inner loop. |
| `bash 40k/tests/run_scenario.sh PATH` | Single scenario, windowed mode. |
| `bash 40k/tests/run_scenarios.sh` | All sp scenarios. `--all` includes mp; `--changed-only` for pre-commit. |
| `python3 40k/tests/check_coverage.py` | Validate coverage.json ↔ scenarios. |
| `40k/tests/scenarios/_schema.md` | Scenario format spec. |
| `.llm/scaled-testing-plan.md` | Living design doc — read first if you're new to this. |

## File locations

- Scenarios: `40k/tests/scenarios/sp/*.json` and `40k/tests/scenarios/mp/*.json`
- Coverage matrix: `40k/tests/coverage.json`
- Runner autoload: `40k/autoloads/ScenarioRunner.gd`
- Headless audit: `40k/tests/run_pretrigger_tests.sh` and `40k/tests/test_*.gd`
- Save fixtures: `40k/saves/` (also `40k/tests/saves/`)
- CI workflow: `.github/workflows/scenarios.yml`
- Pre-commit hook: `.githooks/pre-commit`
- Test outputs: `user://test_results/scenarios/<id>.json` + screenshots
