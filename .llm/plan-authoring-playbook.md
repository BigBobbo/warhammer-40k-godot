# Plan-authoring playbook — repeat "Da Free-Grab Grip" for any army

Written after authoring the first played plan (Orks, hammer_anvil, 2026-08-26,
PR #902). Everything here was learned by doing it once; following this file
should cut the next army's run from a day to a couple of hours. Companion
reading: `40k/docs/PLAN_FORMAT.md` (format), `40k/docs/AI_PLANS_GUIDE.md`
(player view), `40k/tests/bench_baselines/2026-08-25_free_grab_grip.md`
(the measured first run).

## First: decide whether this army can profit from a plan at all

Plan value is **army-dependent** — measured, not assumed. The Orks won
11–1 because 12"-move OC could be routed down layout corridors the
formula doesn't know. The Custodes (M5–6, 11 units) lost with every
variant tried — dispersed, concentrated, and even earmarks-only — because
a fixed anything gives up the formula's one real strength, reactive
counter-deployment, and a HOLD earmark's standing +8.0 pins a slow unit
to one objective all game (see
`40k/tests/bench_baselines/2026-08-26_auric_vice.md`). Ask first: what
does this army know that the formula can't? Speed + layout corridors,
alpha-strike staging, screen geometry are real answers. "Better OC
spreading" is not — the formula already does that dynamically. If there
is no crisp answer, run one cheap probe (earmarks-only plan, 2×6 games
vs the A/A anchor) before spending hours in the editor.

## The loop, in order

1. **Design on paper first** — board geometry, army speed/OC table, scoring
   brackets. Optionally fan out 2–3 tactical lenses and judge them, but
   ALWAYS correct the winner against engine reality (section "Engine facts")
   before placing anything.
2. **Launch the game windowed** (`godot --path 40k --rendering-method
   gl_compatibility`, bridge on 127.0.0.1:9080) and drive the real Plan
   Editor. Never author by writing JSON — the editor session is what catches
   terrain, base shapes and the attached-character footprints.
3. **Measure in the shipped simulator, both seat orders, same seeds**,
   before any talk of shipping.
4. If it wins: ship as an ADDITIONAL plan (layout-bound plans coexist with
   generic ones), update the two pm10 scenario pins, changelog, report,
   delete the leftover `user://ai_plans/` copy.

## Exact UI/API entry points (all verified live)

- Menu setup: the editor reads **its own army picker**,
  `m.plan_editor_army_dropdown` (NOT `player1_dropdown` — setting that one
  silently loads the wrong army). Set `.selected` +
  `emit_signal("item_selected", i)`, confirm with `m._plan_editor_army_id()`,
  set `m.plan_editor_zone_dropdown`, then
  `PlanEditorButton.emit_signal("pressed")`. Options come from
  `m.army_options[i].id` / `m.deployment_options[i].id`.
- FORMATIONS (phase 0): `phase.execute_action({"type":
  "DECLARE_LEADER_ATTACHMENT", "character_id", "bodyguard_id", "player": 1})`
  and `{"type": "DECLARE_RESERVES", "unit_id", "reserve_type":
  "deep_strike"}` (fall back to `strategic_reserves` if refused). Confirm via
  `tree.current_scene._on_formations_confirm_pressed()`. The editor
  auto-resolves the roll-off; you land in phase 1.
- Deployment: `phase.validate_action` / `phase.execute_action` with
  `{"type": "DEPLOY_UNIT", "unit_id", "player": 1, "model_positions":
  [Vector2 px...]}` — px = inches × 40. Use a spiral nudge loop (±0.5"–3")
  around each anchor: validate, nudge, execute. The phase is the referee;
  never pre-compute legality yourself.
- After scripted placements: `tree.current_scene._recreate_unit_visuals()`
  and `_update_deployment_progress()`.
- Intents: `panel = /root/Main/IntentPainterPanel`; set
  `panel.selected_unit = "U_X"` then `panel._set_earmark({"verb": ...,
  "target": ...})` — the same call the buttons and the objective-click make.
  **The panel spawns DEFERRED after the final deployment** — painting in the
  same script that placed the last unit finds no node (and a bare
  `get_node` aborts the script silently, so the failure looks like success).
  Use `get_node_or_null`, wait a frame/second and retry, and after saving
  **read the plan JSON back and assert the `earmarks` count** — a plan that
  saved with 0 earmarks measures as a deployment-only ablation.
- Save: `PlanEditorBanner/PlanEditorBannerRow/PlanEditorSaveButton` →
  dialog fields at `PlanSaveDialog/PlanSaveRoot/Plan{Name,Author,Description}EditRow/...Edit`,
  save button at **`PlanSaveRoot/PlanSaveActions/PlanSaveButton`** (NOT
  directly under PlanSaveRoot — this cost a debugging round).
- Simulator: `PlanSimulator.start({zone_id, layout_id, mission_id, army1,
  army2, plan1, plan2, games, seed_base, difficulty, time_scale: 10.0,
  max_seconds_per_game: 900})`; poll `is_running()` /
  `get_progress_line()`; summary JSON lands in `user://plan_sim_results/`.
  ~3–5 min per 2000pt game at time_scale 10, in-process.

## Engine facts that shape every design

- **Attached characters never use plan placements.** DeploymentPhase P1-66
  auto-deploys them adjacent to their bodyguard. Do NOT anchor or place
  them; declare the attachment and let the phase drop them (in the editor
  this happens automatically when the bodyguard deploys). This was PM-F7's
  root cause.
- **HOLD_OBJECTIVE works on ANY objective id** (+8.0 assignment bonus,
  `PLAN_EARMARK_HOLD_BONUS`), including no-man's-land markers.
  PUSH_CENTER is +6.0 on central objectives. SCREEN withholds the unit from
  the objective passes entirely.
- **Earmark bonuses are sub-threshold priors, not steering** (LLM-commander
  experiment, `2026-08-26_llm_commander.md`): with earmarks consumed in
  10–23 movement records per game, 10 of 12 games still replayed the
  no-plan baseline bit-for-bit — +8 rarely flips an assignment argmax for
  an elite army. A plan's real levers are **deployment placements and
  reserves**; treat earmarks as a tiebreaker, or raise the bonus via
  `profile_fragment` if the plan's identity depends on them.
- **Deep-strike arrival ignores earmarks.** Reinforcement placement scores
  proximity to ANY objective (`REINFORCE_OBJ_NEAR_BASE`); the earmark only
  steers movement after arrival. Never design "arrives AT objective X".
- **11e coherency envelope: keep any formation's span ≤ ~8.8"** (2" to a
  neighbour AND 9" to every other model). A wide picket line is illegal —
  the PM-F4 shape. 11-model mobs: 6×2 at ≤1.6" pitch is safe.
- **Oval bases: read `base_dimensions` before picking pitches.** At
  rotation 0 a bike's `width` (75px = 1.9") runs along **Y**, `length`
  (42px) along X — rank spacing needs ≥3.1" in Y, ~2" in X. Getting this
  backwards fails every bike placement at once.
- **Reserves caps: 50% points / 50% unit count**, attached characters count
  toward the points of a reserved bodyguard.
- **Scoring: primary caps at the "more than 2" bracket** → three held
  objectives is max value; scoring happens in the command phase from round
  2, so END-OF-ROUND-1 positions decide the first score. M12 units at the
  zone edge reach a y=30 objective line on move 1 (hammer_anvil).
- **Plans saved from the editor are layout-bound** (`keys.terrain_layout_id`
  is set). They only auto-match on that layout — so a tuned plan coexists
  with a generic one with no regression surface. A USER plan beats a
  shipped plan at equal match rank; delete the user:// copy after shipping.

## Terrain drill (do this before anchoring anything)

Dump wall/area bounding boxes:
`for t in GameState.state.board.terrain_features:` read `t.piece_class`
("feature" = wall, blocks; "area" = footprint), `t.position`, `t.size`,
`t.can_move_through` (INFANTRY usually true, VEHICLE/MOUNTED false).
Then: which clear corridors reach the objectives? On take_and_hold_mirror_1
both zone-edge flanks are walled against MOUNTED, but the outer 2" board-edge
strips (west of x2.7, east of x41.7) are clear — 3-bike columns fit, 6-bike
mobs do not. Jump INFANTRY ignores the ruins. Route fast OC by corridor,
stage wide mobs in clear pockets as second wave.

## Measurement protocol

- Both seat orders (plan1/plan2 swapped), same `seed_base`, ≥6 seeds each.
  Report the seat-cancelled margin ((arm1 − arm2)/2 of the P1−P2 headline)
  and the win count; check `stalls: 0, timeouts: 0` in the summary.
- **Run an A/A anchor first** (`plan1:"", plan2:""`, same army both seats,
  same seeds): the seat bias can be double-digit VP and per-game variance
  runs sd 15–40, so single-arm numbers are uninterpretable without it.
  Seeded games are deterministic given identical inputs, so **seed-paired
  deltas against the anchor** are the sharpest 6-game comparison — use
  them, not just the arm means.
- `plan_adherence_*` counts only *deployment* records — an earmarks-only
  plan legitimately reports 0/0; prove application via seed-paired margin
  shifts instead.
- The sim headline "mean margin" sign is **P1 − P2** (verified).
- An empty plan string gives that seat the no-plan formula — the honest
  baseline. Beating a foreign-layout shipped plan is a weaker claim.
- The Grip's baseline: 11–1, ≈ +21 VP/game vs the generic shipped plan on
  its own layout. Part of that is domain advantage (the generic plan
  repairs on a foreign layout) — say so; the claim is "layout-tuned beats
  generic on its layout", nothing more.

## Shipping checklist

1. Copy plan into `40k/data/ai_plans/`, set `name` ("Orks — ..."), honest
   `author` (who/how it was made and tested; keep "human review wanted").
2. `sp/pm10_shipped_plan_from_menu.json`: update BOTH the step-1 shipped
   plan list pin and the step-2 filename loop + equality.
3. Delete the `user://ai_plans/` working copy (it outranks the shipped one).
4. Changelog entry in `40k/data/version_history.json` (minor bump).
5. Report in `40k/tests/bench_baselines/`, evidence PNGs in
   `40k/docs/evidence/`, `godot --headless --path 40k --import` for the
   `.import` files.
6. Full suite + the `sp/pm*` windowed batch. Export presets already include
   `data/ai_plans/*.json`.

## Environment traps (all hit at least once)

- **The container reverts the clone and the user data dir.** `git fetch` +
  `git merge --ff-only` at session start, always; the remote is the only
  truth. The runners now checksum-refresh fixtures into `saves/` and
  `user://saves` (`cp -n` never refreshes and once replayed retired stale
  boards through the whole suite).
- A failed `load()` inside a static function **aborts the function
  silently** — never load autoload-referencing scripts from validator-style
  static code; inline what you need.
- `pkill -f` with a pattern matching your own shell kills the shell (exit
  144). Kill by PID.
- `capture_screenshot` returns inline base64 — don't pipe it through a
  truncating JSON parser; read the PNG from `user://test_screenshots/`.
- The editor cannot un-place a unit: get placements right via
  validate-and-nudge, or exit and restart the session.
- **After a simulator run the scene stays on `Main`** (phase 11), so
  re-entering the editor fails with stale declarations. Go back first:
  `tree.change_scene_to_file("res://scenes/MainMenu.tscn")`.
- The scratchpad directory can revert mid-session (an old `mcp_client.py`
  reappeared and silently printed nothing). Keep session tooling under
  `/root/bin/` and re-check file timestamps when a tool goes quiet.
