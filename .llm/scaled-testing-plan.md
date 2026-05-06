# Scaled feature-validation testing — design doc

Living document. Captures the design for a continuous-CI gate that prevents the "Claude says it works, player can't actually use it" failure mode. Edit this file as the design evolves; reference from session-end summaries and PR descriptions.

## Goals

1. **Every PR gated on player-path validation.** No gameplay change merges without a windowed scenario that drives the UI like a player and passes.
2. **No more headless-only "verified" claims.** Headless GDScript tests stay (fast inner loop) but are demoted from merge gate to supplementary check.
3. **Single Claude session at a time.** Coverage tracking is informational, not a coordination primitive.
4. **Multiplayer in scope.** Scenarios support multi-peer execution via the existing `TestModeHandler` command-file protocol.
5. **Rule encoded structurally.** Project `CLAUDE.md` carries the rule so any future session sees it; pre-commit + CI enforce it mechanically.

## Architecture

```
40k/
├── tests/
│   ├── scenarios/                    # NEW — committed test scenarios (player actions)
│   │   ├── _schema.md                # format spec
│   │   ├── sp/                       # single-player
│   │   └── mp/                       # multi-peer
│   ├── run_scenario.gd               # NEW — generic runner (windowed via MCP)
│   ├── run_scenarios.sh              # NEW — batch runner
│   ├── run_pretrigger_tests.sh       # KEEP — fast headless inner-loop suite
│   ├── coverage.json                 # NEW — machine-readable coverage tiles
│   └── check_coverage.py             # NEW — gate: stale entries fail CI
├── .githooks/
│   └── pre-commit                    # NEW — runs scenarios touching changed paths
└── SESSION_PLAYBOOK.md               # NEW — what a Claude session does
```

CI: `.github/workflows/scenarios-windowed.yml` (Linux + Xvfb, on every PR) +
existing `scenarios-headless.yml` equivalent for the GDScript suite.

## Scenario format

Player-action shape, not engine-action shape. The runner uses MCP tools
(`simulate_click`, `capture_screenshot`, `get_node_info`) — never
`dispatch_action` from inside scenarios, since that's the route that masked
past UI bugs.

```json
{
  "id": "co_offer_after_charge",
  "covers": ["fight.stratagem.counter_offensive", "fight.fights_first_pulse"],
  "fixture": "co_pretrigger.w40ksave",
  "rng_seed": 42,
  "steps": [
    { "act": "screenshot", "label": "01_loaded" },
    { "act": "click_unit", "unit_id": "U_WARBOSS_B" },
    { "act": "click_button", "node": "/root/Main/UI/ChargeButton" },
    { "act": "click_unit", "unit_id": "U_CUSTODIAN_GUARD_B" },
    { "act": "expect_dialog_visible", "node": "/root/Main/UI/CounterOffensiveDialog", "timeout_s": 2 },
    { "act": "screenshot", "label": "02_co_dialog_shown" },
    { "act": "click_button", "node": ".../CounterOffensiveDialog/AcceptButton" },
    { "act": "expect_token_modulate", "unit_id": "U_CUSTODIAN_GUARD_B", "color_hint": "fights_first_pulse" },
    { "act": "expect_state", "path": "units.U_CUSTODIAN_GUARD_B.flags.fights_first", "equals": true },
    { "act": "expect_cp_delta", "player": 1, "delta": -2 }
  ],
  "multiplayer": false
}
```

Multi-peer scenarios add a `peers: { host: {steps...}, client: {steps...} }`
section and the runner orchestrates two `--test-mode` subprocesses via the
existing command-file protocol.

## Validation gate

**Hard rule (from CLAUDE.md):** a feature is not verified until a windowed
scenario passes. Pure-math/state changes may be headless-only.

- Pre-commit (Mac local): runs scenarios whose `covers` tags overlap with
  changed file paths. Uses `osascript` to activate the Godot window.
- CI (Linux + Xvfb): runs the full scenario suite + the headless GDScript
  suite + `check_coverage.py`. Xvfb sidesteps the macOS backgrounded-window
  stale-frame issue.
- `coverage.json` is machine-readable; entries claim `last_verified_commit`.
  The gate fails if any entry's last-verified commit is not reachable from
  HEAD or the scenario file is missing.

## Day-by-day rollout

Each day produces a self-contained, testable slice.

| Day | Deliverable |
|---|---|
| 1 | Finish RNG seed plumbing (#329) — TransportManager + MissionManager + Mathhammer; add determinism smoke test proving a seeded scenario reproduces identical dice across 3 runs. |
| 2 | Scenario schema (`_schema.md`) + `run_scenario.gd` — windowed, MCP-driven. Port `test_co_pretrigger.gd` to the first scenario file. |
| 3 | `run_scenarios.sh` batch runner. Port HI + RI to scenarios. Verify the gate has teeth: deliberately break a UI wire and confirm scenario fails. |
| 4 | GitHub Actions workflow (Linux + Xvfb) + Mac pre-commit hook. Both run new scenario suite. |
| 5 | `coverage.json` + `check_coverage.py` + `SESSION_PLAYBOOK.md`. CLAUDE.md update done already. |
| 6 | First multi-peer scenario (port one from `tests/network/`). Sync assert passes via multi-peer runner. |
| 7 | Migrate 3-5 audit findings from `AUDIT_REPORT.md` markdown into scenario files. coverage.json shows ≥10 covered tiles. |

## Out of scope (deferred)

- BDD / Gherkin authoring layer
- Multi-Claude parallel orchestration
- Visual-diff perceptual screenshot harness — single `screenshot_match`
  assert with crude tolerance is enough for now
- Replacing `run_pretrigger_tests.sh` — both runners coexist permanently

## Open questions

- Whether `coverage.json` lives under `40k/tests/` or top-level `audit/`
  (current default: `40k/tests/`)
- Whether pre-commit runs `--changed-only` or full suite (current default:
  changed-only)
