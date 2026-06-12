# tests/unit — legacy GUT suite (status: unmaintained)

Status recorded 2026-06-10 during the architecture overhaul (ISS-011):

- This GUT-based suite is NOT part of the maintained gate
  (`tests/run_pretrigger_tests.sh` + `tests/run_scenarios.sh`).
- Running it currently produces ~94 failing assertions (error-ordering and
  wording drift vs. the current RulesEngine) and the run hangs on network
  listeners until killed.
- It is still referenced by `run_deployment_tests_only.sh`,
  `run_multiplayer_tests.sh`, `validate_all_tests.sh`,
  `validate_tests_with_timeout.sh` — those runners share its status.

Triage decision deferred: the fight/charge/transport tests here cover 10th
edition behavior that the 11e migration rewrites (ISS-049/050/058). Mine
them for fixture ideas while implementing those issues, then delete the
suite (or port the few still-relevant cases into the maintained runners).
Everything is preserved in git history regardless.
