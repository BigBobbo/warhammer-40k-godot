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

## Anti-pattern: pin tests are NOT validation (2026-05-06 lesson)

A "pin test" — a headless `_check("func X defined", "func X" in src)` —
proves the code shape is present. It is a **regression net** that catches
silent reverts. It is **not** validation that the feature works.

A screenshot labelled `running_with_patches_loaded` or
`after_implementation` shows the game window with the patch in memory; if
the feature was never triggered in that screenshot, it is a **marker**, not
evidence.

**To claim an audit task is validated, you must:**

1. Drive the feature path live via the MCP bridge:
   - `dispatch_action({type: "X", ...})` and assert `success: true`
   - or `execute_script` calling the new helper and read the return
   - or `simulate_key_press` / panel toggle to open the new UI
2. Inspect the resulting state via `execute_script` reading the diff /
   updated flags / spawned dialog / tween-in-progress
3. Capture a screenshot showing the **feature's effect** — the dialog
   rendered, the token at the new position, the panel listing real rows.
   The default game screen does not count.

If the feature has no UI affordance (pure-math helper), step 3 is the
return value of step 1/2 captured in the conversation transcript; an
explicit screenshot is optional. Everything with a UI surface needs the
in-game effect captured.

**Reference**: `~/.claude/projects/-Users-robertocallaghan-Documents-claude-godotv2/memory/feedback_pin_tests_arent_live_validation.md`

## Anti-pattern: do NOT assume — validate, and never claim a limitation you haven't proven (2026-05-30 lesson)

Stating something as fact without running it is the single most frustrating
failure mode in this project. It has happened repeatedly. STOP.

**Rules — these are non-negotiable:**

1. **Never report a tool/harness/engine limitation you have not reproduced and
   root-caused.** "The MCP bridge can't drive X", "the test harness can't do
   Y", "this isn't reachable headless" are CLAIMS, not facts, until you have
   the failing output AND the reason. If a call returns an unexpected result
   (e.g. `success:true` but empty state), that is a lead to investigate, not a
   conclusion — read the handler source and find out *why* before reporting.
   (Real example: `BEGIN_ADVANCE` returned `success:true` with empty
   `active_moves`; the real cause was a `_awaiting_reroll_decision` pause that
   needed a follow-up `DECLINE_COMMAND_REROLL` — the harness was fully capable.)

2. **Trace the code path before declaring how something behaves.** If you find
   yourself writing "should", "probably", "I believe", or "likely" about
   behaviour you could just run, you are guessing. Run it.

3. **When you simplify or stub to make a test pass** (e.g. setting a value
   manually instead of driving the real flow), say so explicitly AND treat it
   as incomplete validation. Then go drive the real flow. Do not present a
   manual-setup test as proof the real path works.

4. **If you genuinely cannot validate something, say "I have not validated
   this" plainly** — do not dress an assumption up as a finding. An honest
   "unverified" is acceptable; a confident wrong claim is not.

Before writing "X can't be done" or "X works", ask: *did I actually run it and
read the result?* If not, do that first.
