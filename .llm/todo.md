# TestModeHandler / multi-peer integration tests — remaining issues

Two pre-existing infrastructure issues uncovered when commit `9d77ed7` made the `_handle_load_save` and `_handle_get_game_state` fixes that let the multi-peer integration suite actually progress past early-fail points. Both are blocking the shooting-side tests from clearing.

Validator for both: `bash 40k/tests/run_multiplayer_tests.sh`. Audit gate (`bash .claude/scripts/run_validation.sh`) stays at 423 passed / 0 failed across 17 tests; that's the no-regression bar. The multi-peer pass/fail delta is the success bar — currently 27 passed / 11 failed across 39 tests / 5 scripts. Goal: reduce the failure count toward 0.

---

- [ ] Fix command-file double-execution race in TestModeHandler

  Symptom (verified in the `9d77ed7` commit message and the `/tmp/mp_run4.log` trace): when a TestModeHandler action handler awaits internally — e.g. `_handle_use_grenade_stratagem` running the stratagem flow which yields to NetworkManager / signal handlers — the autoload's command-file scan loop re-picks up the same command file before the handler writes its result. The first execution succeeds and mutates state; the second clobbers the result file with `"No active phase instance"` because the phase has been torn down by the time the duplicate execution runs. Concrete trace from the grenade test (`test_multiplayer_dice_log_sync.gd`):

  ```
  TestModeHandler: Processing command file host_40793_cmd_004.json   ← 1st
  TestModeHandler: Executing action: use_grenade_stratagem
  [PhaseManager] get_current_phase_instance returning: Node          ← phase exists
  ShootingPhase: Matched USE_GRENADE_STRATAGEM
  StratagemManager: GRENADE rolled [1, 3, 3, 3, 2, 6] — 1 mortal wound(s)   ← REAL execution
  StratagemManager: GRENADE applied 1 mortal wounds...
  TestModeHandler: Processing command file host_40793_cmd_004.json   ← 2nd (race)
  TestModeHandler: Executing action: use_grenade_stratagem
  [PhaseManager] get_current_phase_instance returning: null          ← phase gone
  TestModeHandler: Result written to: host_40793_cmd_004_result.json ← writes FAILURE
  [Test] Action completed: success=false, message=No active phase instance
  ```

  Find the command-file scan loop in `40k/autoloads/TestModeHandler.gd` (search for `_execute_command_file`, `Processing command file`, or the `_process` / scanner pattern that picks up new JSON files in the commands directory). Implement de-dup. Two viable approaches:

  1. **In-flight set** (simplest) — maintain a `_commands_in_flight: Dictionary` (or Array) keyed by filename. On pickup, skip if the filename is already in the set. On completion (after writing the result), remove from the set.

  2. **Atomic rename on pickup** — immediately rename the command file (e.g., to `<name>.processing`) before invoking the handler. The scanner only picks up `.json` files, so the renamed file won't be re-scanned.

  Approach 1 is simpler and less filesystem-y. Prefer it unless atomic rename is already the project's pattern elsewhere.

  Acceptance:
  - The trace above no longer shows a duplicate `Processing command file <name>` entry for the same filename within a single handler invocation.
  - Re-run `bash 40k/tests/run_multiplayer_tests.sh`. The grenade test (`test_multiplayer_dice_log_sync.gd`) now sees the success result that the first execution actually produced. Expected delta: at least the 3 shooting-feature tests in the new test files (visuals select-shooter, dice-log grenade, save-dialog basic-broadcast) should pass (or at least no longer fail with "No active phase instance").
  - Audit suite stays green at 423/17.
  - The multi-peer total failure count drops from 11. Exact target depends on how many failures the race was masking; aim for ≤8.

  Out of scope: any deeper refactor of the command-file IPC. Just stop the double execution.

  Files: `40k/autoloads/TestModeHandler.gd`. Possibly add a small headless test under `40k/tests/test_test_mode_handler_command_dedupe.gd` exercising a synthetic command file twice and asserting only one execution, but only if that's straightforward — the multi-peer trace is the load-bearing validator.

---

- [ ] Make multi-peer integration tests advance from FORMATIONS to DEPLOYMENT before deployment assertions

  Symptom (verified in `/tmp/mp_run4.log`): peers spawned by `GameInstance.gd` with `--auto-host` / `--auto-join` boot into `FORMATIONS` phase (enum value 0 in `GameStateData.Phase`), not `DEPLOYMENT` (enum value 1). The `9d77ed7` fix to `_handle_get_game_state` now reads this correctly and reports `"current_phase": "Formations"`, which surfaces an existing bad assumption in `40k/tests/integration/test_multiplayer_deployment.gd` and `test_multiplayer_network.gd` — the deployment-driving tests assert `expected_to_equal("Deployment")` immediately after `launch_host_and_client()`. Before the get_game_state fix these failed silently as `"Unknown" vs "Deployment"`; now they fail more honestly as `"Formations" vs "Deployment"`. Same underlying issue.

  In Warhammer 40k 10e the actual game flow is: Formations declarations → Deployment → first Command Phase. The multiplayer boot path drops both peers into Formations because that's how a real game starts. Tests that need to drive deployment must advance the host (and client) past Formations first.

  Pick the cleanest path:

  1. **Add a `complete_formations` TestModeHandler action** that wraps the host-side completion of the Formations phase (whatever real-game path takes Formations → Deployment), then call it from each deployment-driving test's setup. Most rules-faithful but requires understanding what "complete formations" means in this codebase.
  2. **Add a `transition_to_phase` TestModeHandler action** that takes a `phase` enum int and calls `PhaseManager.transition_to_phase(phase)` on whichever peer received it. Lower-fidelity but minimal scope. Tests can invoke `simulate_host_action("transition_to_phase", {"phase": GameStateData.Phase.DEPLOYMENT})` explicitly.
  3. **Update each affected test method** to advance the phase via existing actions (if any path supports it).

  (1) is the "right" fix; (2) is pragmatic and unblocks the integration suite faster. Pick (2) unless (1) is a one-line wrap because there's already a `complete_formations` flow in `FormationsPhase.gd`.

  Acceptance:
  - Re-run `bash 40k/tests/run_multiplayer_tests.sh`. The `test_multiplayer_deployment.gd` failures of the form `["Formations"] expected to equal ["Deployment"]:  Host should be in Deployment phase` clear (and same for client and the network tests' analog).
  - Audit suite stays green at 423/17.
  - The multi-peer total failure count drops further from wherever the race-fix task leaves it. Aim for ≤4 remaining failures (some failures may be downstream cascades that stay broken until both fixes land).

  Out of scope: rewriting the deployment tests' actual deployment logic; auditing whether all 4 prior integration tests under `test_multiplayer_deployment.gd` still make sense in 10e.

  Files: `40k/autoloads/TestModeHandler.gd` (new action handler), `40k/tests/integration/test_multiplayer_deployment.gd` (callers), possibly `40k/tests/integration/test_multiplayer_network.gd` if it has the same assertion pattern, possibly `40k/tests/helpers/MultiplayerIntegrationTest.gd` if a `before_each` advance is the cleanest fit.
