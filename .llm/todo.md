# Multi-peer test infrastructure (cont.)

- [ ] Upgrade three multi-peer integration tests with real behavioral assertions

  After `8744fef` added 6 shooting-phase handlers to TestModeHandler (`select_shooter`, `assign_target`, `clear_assignment`, `confirm_targets`, `complete_shooting_for_unit`, `use_grenade_stratagem`) AND a shooting-phase fixture has been added to `40k/tests/saves/shooting_phase.w40ksave` (phase=8, copied from a real game in shooting state), the three multi-peer integration tests in `40k/tests/integration/` (`test_multiplayer_dice_log_sync.gd`, `test_multiplayer_save_dialog_retry.gd`, `test_multiplayer_shooting_visuals.gd`) can now drive real shooting actions across the wire.

  Currently those tests fall back to connection-only assertions because `MultiplayerIntegrationTest.get_shooting_test_save()` previously returned a non-existent save. With the fixture now committed they can load it via `simulate_host_action("load_save", {"save_name": "shooting_phase"})`.

  For each test file, upgrade at least ONE test method to drive a real scenario and assert behavioral state on both peers. Keep existing static-source contract assertions where present — those are useful regression detectors.

  Specific upgrades:

  - **`test_multiplayer_shooting_visuals.gd`** → pick the most natural test (e.g. select-shooter or assign-target broadcast). After loading the shooting fixture: `simulate_host_action("select_shooter", {"actor_unit_id": "<id from get_game_state>"})`, then `simulate_client_action("get_game_state", {})` and assert the client's ShootingPhase has the same `active_shooter_id`.

  - **`test_multiplayer_dice_log_sync.gd`** → pick the grenade test method. After loading the shooting fixture and selecting a unit with grenades: `simulate_host_action("use_grenade_stratagem", {"actor_unit_id": "...", "target_unit_id": "..."})`, then `simulate_client_action("get_game_state", {})` and assert the client's last-action dice block contains the grenade roll (count = 6 D6 per the stratagem rules).

  - **`test_multiplayer_save_dialog_retry.gd`** → pick the basic-broadcast test (NOT the retry path — that needs `inject_save_dialog_drop` which is a separate task). Drive `select_shooter` → `assign_target` → `confirm_targets` and assert the client received a `saves_required` broadcast with a `save_broadcast_id` field.

  Fixture details: `40k/tests/saves/shooting_phase.w40ksave` is a real Ork-vs-something game in shooting phase, turn 1, ~200KB. Use `get_game_state` on the host immediately after load to enumerate available units, then pick units that fit each test's needs (e.g. a unit with grenades for the grenade test).

  Acceptance:
  - Each of the three files syntax-checks (`godot --headless --check-only --script tests/integration/test_multiplayer_<name>.gd` exits 0)
  - Existing audit suite still 423 passed / 0 failed across 17 tests (no regression — these tests aren't in `run_pretrigger_tests.sh` and must not be added to it)
  - At least one test method per file has REAL behavioral assertions about state changes on the client peer, not just connection / phase sync
  - DO NOT try to actually run `run_multiplayer_tests.sh` — it needs the user's local environment with real Godot processes and port binding
  - Each upgraded test method has a docstring explaining what behavior it verifies and what limitations remain
  - If any prior manual-run entries in `TESTS_NEEDED.md` are now actually automated, update accordingly

  Files: three test files in `40k/tests/integration/`, possibly `TESTS_NEEDED.md`. Do NOT modify `MultiplayerIntegrationTest.gd` or `TestModeHandler.gd` — those are stable surfaces.
