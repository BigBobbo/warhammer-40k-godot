# Multi-peer test infrastructure (cont.)

## Test-upgrade tasks (one file each, run sequentially)

Background context that applies to all three:
- A real shooting fixture is now committed at `40k/tests/saves/shooting_phase.w40ksave` (phase=8, turn 1, Ork-vs-something) — `MultiplayerIntegrationTest.get_shooting_test_save()` resolves to it.
- Six new shooting-phase handlers exist in `40k/autoloads/TestModeHandler.gd` (lines ~985+): `select_shooter`, `assign_target`, `clear_assignment`, `confirm_targets`, `complete_shooting_for_unit`, `use_grenade_stratagem`. Reference test for handler payload shapes: `40k/tests/test_test_mode_handler_shooting.gd`.
- Each test should load via `simulate_host_action("load_save", {"save_name": "shooting_phase"})`, then enumerate units via `simulate_host_action("get_game_state", {})` to pick concrete `actor_unit_id` / `target_unit_id` values, then drive the scenario.
- Validation gate caveat: `run_validation.sh` runs single-process headless and does NOT exercise the multi-peer suite. The gate only verifies "no regression in existing tests." Don't add the integration tests to `run_pretrigger_tests.sh`.
- Audit suite baseline: 423 passed / 0 failed across 17 tests. Must stay at 423/17.

---

- [x] Upgrade test_multiplayer_shooting_visuals.gd with one real behavioral assertion
  Pick the most natural test method (likely the select-shooter or assign-target broadcast test) and upgrade it from connection-only fallback to a real scenario. The flow:
  1. `await launch_host_and_client()` + `wait_for_connection()` (existing pattern).
  2. `simulate_host_action("load_save", {"save_name": "shooting_phase"})` — assert success.
  3. `simulate_host_action("get_game_state", {})` — read the result, pick an `actor_unit_id` for the active player from the units list.
  4. `simulate_host_action("select_shooter", {"actor_unit_id": <id>})` — assert success.
  5. `simulate_client_action("get_game_state", {})` — read client's view, assert the client's ShootingPhase reports the same `active_shooter_id`. (May need `verify_game_state_sync()` first to give the broadcast time to propagate.)
  6. Add a docstring stating: what behavior is verified (host-driven shooter selection visible on client), what limitation remains (range_visual child counting not exercised because `get_game_state` doesn't expose controller state — would need a future `get_controller_state` action).
  Other test methods in the file: leave them as-is. Only upgrade ONE.
  Acceptance: file syntax-checks (`godot --headless --check-only --script tests/integration/test_multiplayer_shooting_visuals.gd` exits 0); existing audit suite still 423/17.
  Files: `40k/tests/integration/test_multiplayer_shooting_visuals.gd`.

- [x] Upgrade test_multiplayer_dice_log_sync.gd with one real behavioral assertion
  Pick the grenade test method and upgrade it from connection-only fallback to a real grenade roll over the wire. The flow:
  1. `await launch_host_and_client()` + `wait_for_connection()`.
  2. Load the shooting fixture: `simulate_host_action("load_save", {"save_name": "shooting_phase"})`.
  3. Read `get_game_state` to find a unit eligible for the grenade stratagem AND a target unit. If no eligible unit/target combination exists in the fixture, document that gap and pick whatever shooter+target you can to at least exercise the dispatch path.
  4. `simulate_host_action("use_grenade_stratagem", {"actor_unit_id": <shooter>, "target_unit_id": <target>})`. The grenade stratagem rolls 6 D6.
  5. `simulate_client_action("get_game_state", {})` and inspect the result for the dice block. Per `f67b1ee`'s static-source contract, `result["dice"]` carries the grenade roll; assert the count of dice values is 6 and each is in 1..6.
  6. Docstring: verifies host-driven grenade roll appears in client's dice log; limitations are around what the fixture happens to contain.
  Only upgrade ONE method.
  Acceptance: file syntax-checks; audit suite still 423/17.
  Files: `40k/tests/integration/test_multiplayer_dice_log_sync.gd`.

- [x] Upgrade test_multiplayer_save_dialog_retry.gd with one real behavioral assertion
  Pick the basic-broadcast test method (NOT the retry path — that needs `inject_save_dialog_drop` which is queued separately). The flow:
  1. `await launch_host_and_client()` + `wait_for_connection()`.
  2. Load the shooting fixture.
  3. Drive a full shoot: `select_shooter` → `assign_target` (read `get_game_state` to pick a valid weapon_id and model_ids; the assign_target handler in TestModeHandler nests target/weapon/model_ids under `payload`) → `confirm_targets`. This triggers save resolution and emits `saves_required`.
  4. `simulate_client_action("get_game_state", {})` — assert the most recent save broadcast carries a `save_broadcast_id` field (string starting with `sbid-`).
  5. Docstring: verifies the saves_required broadcast pipeline works end-to-end on real peers; limitation is that delivery failure / retry budget cannot be exercised without a `inject_save_dialog_drop` hook.
  Only upgrade ONE method.
  Acceptance: file syntax-checks; audit suite still 423/17.
  Files: `40k/tests/integration/test_multiplayer_save_dialog_retry.gd`.
