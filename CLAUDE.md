The warhammer core rules that this game is replicating can be found here: https://wahapedia.ru/wh40k10ed/the-rules/core-rules/

The Godot documentation can be found here: https://docs.godotengine.org/en/4.4/

The project we are working on is located at /Users/robertocallaghan/Documents/claude/godotv2

Do not remove debugging logs unless specifically asked to do so.

If godot is not running in the command line run export PATH="$HOME/bin:$PATH" and try again.

The debug output of godot is being piped to files in the format /Users/.../Library/Application Support/Godot/app_userdata/40k/logs/debug_YYYYMMDD_HHMMSS.log
As the godot output is not always reachable, ensure that all logging is also saved to this file.

## Feature validation rule (project gate)

A feature is **not** considered verified until a **windowed scenario** drives the player path end-to-end against the running UI and passes:

- Windowed scenarios live under `40k/tests/scenarios/` and are driven via the `addons/godot_mcp` bridge — they `simulate_click` real buttons, assert via `get_node_info` / `capture_screenshot`, and only check `GameState` as a secondary check.
- Headless GDScript tests (`tests/test_*.gd`, `run_pretrigger_tests.sh`) are necessary but **not sufficient**. They validate that the engine accepted an action; they do NOT validate that the UI exposes that action to a player. Past sessions have closed features as "verified" based on headless-only evidence and the player could not actually use them — do not repeat this.
- Any commit that adds or changes player-facing behavior MUST add or update a windowed scenario and prove it passes (`bash 40k/tests/run_scenarios.sh tests/scenarios/<id>.json`) before the commit lands.
- Pure-math / pure-state changes (RulesEngine internals, save/load round-trips, autoload state) MAY be verified headless-only; everything that has a UI affordance must be windowed.
- Reference: `40k/tests/TESTING_METHODOLOGY.md` and `SESSION_PLAYBOOK.md`.
