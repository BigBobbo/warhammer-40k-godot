# Multi-peer test infrastructure

- [x] Add shooting-phase action handlers to TestModeHandler.gd
  Currently `40k/autoloads/TestModeHandler.gd` `_execute_command` handles only 8 deployment-related actions (`load_save`, `deploy_unit`, `undo_deployment`, `complete_deployment`, `get_game_state`, `get_available_units`, `capture_screenshot`, `save_game_state`). The multi-peer integration tests added in `f67b1ee` (`test_multiplayer_dice_log_sync.gd`, `test_multiplayer_save_dialog_retry.gd`, `test_multiplayer_shooting_visuals.gd`) cannot drive shooting actions across the wire because no shooting handlers exist — they fall back to connection-only assertions.

  Add the following new handlers, each delegating to the same code path the UI uses by calling `phase.execute_action({"type": "<UPPERCASE>", ...})` on the active `ShootingPhase` instance:
  - `select_shooter` (params: `actor_unit_id`) → SELECT_SHOOTER
  - `assign_target` (params: read `ShootingPhase.gd` for the exact ASSIGN_TARGET payload — typically `actor_unit_id`, `target_unit_id`, `weapon_id`, `model_ids`) → ASSIGN_TARGET
  - `clear_assignment` (params: `actor_unit_id`) → CLEAR_ASSIGNMENT (current weapon's assignment)
  - `confirm_targets` (params: `actor_unit_id`) → CONFIRM_TARGETS (resolves all assignments for the active shooter)
  - `complete_shooting_for_unit` (params: `actor_unit_id`) → COMPLETE_SHOOTING_FOR_UNIT
  - `use_grenade_stratagem` (params: `actor_unit_id`, `target_unit_id`) → USE_GRENADE_STRATAGEM

  Pattern: copy `_handle_deploy_unit()`'s structure. Each handler validates required params and returns a clear error dict if missing; locates the active ShootingPhase via `PhaseManager.get_current_phase()` (or whatever the deployment handler uses); verifies the phase is a `ShootingPhase`; calls `phase.execute_action(...)`; returns `{"success": bool, "result": <phase result>, "message": ...}`. Wire each new action into the `match action` block in `_execute_command()` (lines 491+ in `TestModeHandler.gd`).

  Acceptance: write a headless regression test `40k/tests/test_test_mode_handler_shooting.gd` that:
  - Loads a shooting-ready fixture (the simplest path: load one of the existing pretrigger saves like `co_pretrigger.w40ksave` or `hi_pretrigger.w40ksave` — they're already deep into a turn — and use `phase_mgr.transition_to_phase(GameStateData.Phase.SHOOTING)` if needed)
  - Invokes each new handler via `TestModeHandler._execute_command({"action": "<name>", "parameters": {...}})` directly (not via command-file IPC; just call the function)
  - Asserts the returned Dictionary has the right shape (`success`, `result`, `message` keys)
  - Asserts a real side-effect on the phase / GameState after each call (e.g., after `select_shooter`, the active phase's active-shooter-id matches; after `assign_target`, an assignment record exists; etc.)
  - Wires the test into `40k/tests/run_pretrigger_tests.sh`
  - `bash .claude/scripts/run_validation.sh` must exit 0 with all assertions passing (current baseline: 359 across 16 tests; adding this test should bump both)

  NOT in scope: synthetic delivery-failure injection hooks for the save-dialog retry path. That's deeper plumbing in `NetworkManager.gd` that warrants a separate task.

  Files: `40k/autoloads/TestModeHandler.gd`, new `40k/tests/test_test_mode_handler_shooting.gd`, `40k/tests/run_pretrigger_tests.sh`.
