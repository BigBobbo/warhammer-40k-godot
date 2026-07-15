The warhammer core rules that this game is replicating can be found here: https://wahapedia.ru/wh40k11ed/the-rules/core-rules/ (11th edition — the current edition, released June 2026)

The Godot documentation can be found here: https://docs.godotengine.org/en/4.4/

The project we are working on is located at /Users/robertocallaghan/Documents/claude/godotv2

Do not remove debugging logs unless specifically asked to do so.

## End-of-task TLDR (include in EVERY message back to the user after completing work)

When you finish a piece of work, end your reply with a succinct TLDR
covering:

- **Ask**: one line on what was requested.
- **Issue**: what was wrong / the root cause (if applicable).
- **Change**: what you actually did.
- **Flags**: anything else worth calling out — risks, follow-ups,
  things not validated, assumptions made.

Keep it tight — a few bullets, not paragraphs. This applies to
implementation work, not to short Q&A replies.

## Version / changelog (update on EVERY player-facing change)

The main menu shows the current version + a "What's New" summary so it is easy
to tell which build is running (e.g. the itch.io release vs the latest GitHub
branch). The single source of truth is `40k/data/version_history.json`
(newest release first), surfaced via `40k/scripts/VersionInfo.gd` and rendered
by `MainMenu._create_version_display()`.

**From now on, whenever you make a player-facing change, PREPEND a new entry to
`40k/data/version_history.json`** before committing:
- Bump `version` (semver: patch for fixes, minor for new features).
- Set `date` to the day the change was made (YYYY-MM-DD).
- Write a one-line `summary` and a `changes` bullet list a player would understand.

Pure-internal changes (refactors, tests, tooling) do not need a new entry.

If godot is not running in the command line run export PATH="$HOME/bin:$PATH" and try again.

The debug output of godot is being piped to files in the format `<godot-userdata>/40k/logs/debug_YYYYMMDD_HHMMSS.log`.
The userdata dir is platform-specific:
- macOS (local): `~/Library/Application Support/Godot/app_userdata/40k/`
- Linux / remote container: `~/.local/share/godot/app_userdata/40k/`

Never hardcode either path — resolve it at runtime with `ProjectSettings.globalize_path("user://logs/")`, or just call the MCP `get_log_path` / `read_debug_log` commands, which return the absolute path for the current machine. As the godot stdout is not always reachable, ensure all logging is also saved to this file.

## You CAN run the game AND screenshot the UI — even in a headless / remote container

This is the single most important operational fact, and past sessions
(including 2026-05-30) wrongly assumed the opposite and "fell back" to
headless-only validation. **Do not repeat that mistake.** The `godot` shim on
`$HOME/bin` auto-wraps the binary with `xvfb-run` (1920×1080) and the GL
compatibility renderer backed by Mesa **llvmpipe** software rendering — no GPU
required. The full UI renders and the in-game MCP bridge comes up.

First run in a fresh clone/container — build the import + global-class cache once:

```bash
export PATH="$HOME/bin:$PATH"
godot --headless --import          # imports resources, writes .godot/global_script_class_cache.cfg
```

Then launch the real game windowed (the shim provides the virtual display):

```bash
godot --path 40k --rendering-method gl_compatibility > /tmp/game.log 2>&1 &
# Wait for the bridge, do NOT sleep-guess:
until grep -q "GodotMCP] Listening" /tmp/game.log; do sleep 0.5; done
```

The bridge then listens on `127.0.0.1:9080` (runtime) and `9081` (editor). Drive
it from an MCP host (`godot-mcp/build/runtime_bridge.js`) or, when no host is
wired up, a tiny NDJSON-over-TCP client: send `{"id":N,"command":"...","params":{}}\n`,
read one JSON line back per request. `capture_screenshot` writes a full-res PNG
under `user://test_screenshots/` and returns an inline image you can view.

If — after actually trying the above — you genuinely cannot run the game or
capture a screenshot, you MUST **flag it explicitly to the user and explain
what you tried and how it failed.** Never silently downgrade to headless-only
and never claim a feature is verified without the evidence the gate requires.

## Updated MCP bridge command set (addons/godot_mcp)

Beyond the originals (`get_board_state`, `dispatch_action`, `move_unit_to`,
`get_legal_actions`, `select_unit`, `transition_to_phase`, `get_scene_state`,
`get_node_info`, `simulate_click`, `capture_screenshot`, …) the bridge now also
exposes — prefer these for validation:

- `verify_delivery` — **the one-call gate.** Checks scene-tree integrity,
  required autoloads, that the debug log has no `ERROR` lines (optionally
  `since_marker`), and any GDScript `assertions` you pass over live state.
  Returns `verdict: PASS|FAIL`. Run it after driving a feature.
- `read_debug_log` — newest `debug_*.log` bucketed into error/warning/info/debug
  counts. Use it to assert "no errors fired" instead of grepping. Supports
  `tail`, `since_marker`, `levels`.
- `scene_snapshot` + `diff_snapshot` — capture a path→state index, then diff
  before/after (or vs. the live tree) to prove only the intended nodes moved
  (reports field-level changes, e.g. `visible: [true, false]`).
- `chain_verify` — pass your `claim`; returns adversarial challenge questions +
  live log evidence. Answer them honestly before closing a task.
- `execute_script` — now supports **multi-line** mode (`multiline: true` or any
  newline): full statements, `return`, autoloads by global name. The target node
  is bound as `node` and the scene tree as `tree` — call methods on those
  (`tree.get_node_count()`), not bare. Single-line still uses the Expression path.
- `write_script` — refuses to overwrite an existing file without `overwrite: true`,
  and honours the `GODOT_MCP_ALLOWED_WRITE_PATHS` allow-list when set.

Reference: `40k/addons/godot_mcp/README.md`.

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

0. Run the game (see "You CAN run the game…" above) — this is possible in the
   remote container, not just locally. `scene_snapshot` the relevant subtree
   first if you want a before/after diff.
1. Drive the feature path live via the MCP bridge:
   - `dispatch_action({type: "X", ...})` and assert `success: true`
   - or `execute_script` (now multi-line) calling the new helper and read the return
   - or `simulate_click` / `simulate_key_press` / panel toggle to open the new UI
2. Inspect the resulting state:
   - `diff_snapshot` against your before-snapshot to see exactly which nodes
     changed, and/or `execute_script` reading the updated flags / spawned dialog
   - `read_debug_log` (or `verify_delivery`'s `log.no_errors` check) to confirm
     **no ERROR / SCRIPT ERROR fired** while exercising the path
3. Capture a screenshot showing the **feature's effect** — the dialog
   rendered, the token at the new position, the panel listing real rows.
   The default game screen does not count.
4. Run `verify_delivery` with the relevant `expected_phase` / `assertions` as a
   final gate; it should return `verdict: PASS`. Optionally run `chain_verify`
   and answer its questions before declaring done.

If the feature has no UI affordance (pure-math helper), step 3 is the
return value of step 1/2 captured in the conversation transcript; an
explicit screenshot is optional. Everything with a UI surface needs the
in-game effect captured. If you could not produce the screenshot/MCP
evidence, say so explicitly and why — do not fail silently.

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
