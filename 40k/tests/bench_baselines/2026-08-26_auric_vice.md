# Custodes plan attempt — "Auric Vice" v1/v2/v3 (2026-08-26): negative result

The second run of the plan-authoring loop (playbook:
`.llm/plan-authoring-playbook.md`), this time for `custodes_lions` on
hammer_anvil / take_and_hold_mirror_1 / take_and_hold — the same board the
Ork plan "Da Free-Grab Grip" won 11–1 on. **Result: negative. No Custodes
plan ships.** Three mechanistically different variants all measured at or
below the no-plan formula, and per the pre-stated bar ("ship only a clear
winner") the honest deliverable is this report, not a plan.

All arms: 6 games, seeds 5001–5006, difficulty 1, time_scale 10, 22 units
on the table, zero stalls / zero timeouts in every run. Headline margin
sign is P1 − P2. Opponent seat is always the no-plan formula
(`plan1:""` / `plan2:""` = the AIController's built-in deployment and
targeting heuristics) — the honest baseline, per the playbook. The plan
JSONs as measured are archived next to this report in `plans/`.

## The variants

- **Auric Vice (v1, dispersed)** — authored live in the Plan Editor the way
  a player would (own army picker, validate-and-nudge placements, intent
  painter, save dialog). 6 placements, 500 pts in deep-strike reserve
  (Allarus + a Guard brick), 3 Blade Champion attachments, 8 earmarks
  spreading OC across home, center and both no-man's-land objectives.
- **Auric Vice II (v2, concentrated)** — second iteration after v1 lost:
  7 placements massed toward center, only the Allarus in reserve. The
  intent-painting step silently failed (the IntentPainterPanel spawns
  deferred after the final deployment; the script painted into a
  not-yet-spawned node), so the saved file had **0 earmarks** — measured
  honestly as a deployment-only ablation. The trap is now in the playbook.
- **Auric Directives (v3, earmarks-only)** — mechanistically different
  probe: empty `placements`/`order` so the formula keeps its own
  deployment, plan supplies only the 3 attachments, the Allarus
  deep-strike reserve, and 7 earmarks (Prosecutors hold home, two Guard
  bricks hold center, one holds nml_2, two push center, Allarus holds
  nml_1). Validated 0 errors / 0 warnings.

## Measurements

| Arm | Plan seat | W–L (plan) | Headline (P1−P2) | Plan-seat margin |
|-----|-----------|-----------|------------------|------------------|
| A/A anchor (no plan either seat) | — | — | +10.0 ± 29.1 (P1 4–2) | — |
| v1 arm1 | P1 | 3–3 | −6.7 ± 40.5 | −6.7 |
| v1 arm2 | P2 | 1–5 | +37.0 ± 24.9 | −37.0 |
| v2 arm1 (0 earmarks) | P1 | 2–4 | −11.8 ± 14.1 | −11.8 |
| v3 arm1 | P1 | 1–5 | −29.7 ± 26.0 | −29.7 |
| v3 arm2 | P2 | 2–4 | −0.8 ± 27.8 | +0.8 |

Per-seed headline margins (all runs share seeds 5001–5006, and a seeded
game is deterministic given identical inputs, so cross-run per-seed
differences are attributable to the plan):

| Seed | A/A | v3 arm1 | v3 arm2 |
|------|-----|---------|---------|
| 5001 | −20 | −41 | −54 |
| 5002 | +4 | −8 | +4 |
| 5003 | +64 | −36 | +26 |
| 5004 | −22 | −19 | +25 |
| 5005 | +10 | −77 | −17 |
| 5006 | +24 | +3 | +11 |

- **Seat bias**: the A/A anchor puts it at ≈ **+10 VP toward P1** on this
  mirror (consistent with the ≈+15 implied by the v1 pair). Raw single-arm
  numbers are uninterpretable without it — sd per game is 14–40 VP.
- **v1 seat-cancelled effect ≈ −21.9 VP/game** ((−6.7 − 37.0)/2), 4–8 in
  games.
- **v2** (single arm as P1): −11.8 raw ≈ **−21.8 vs the anchor**.
- **v3 arm1** seed-paired vs A/A: mean delta **−39.7** (5 of 6 seeds
  down), se ≈ 16.4 — significantly harmful as P1. **v3 arm2** seed-paired:
  +10.8, se ≈ 12.7 — noise. Seat-cancelled ≈ **−14.4 VP/game**, 3–9 in
  games.
- `plan_adherence_p1/p2` counts only *deployment* records
  (`PlanSimulator._plan_adherence`), so v3's 0/0 is expected for a
  placement-free plan, not a loading failure; the seed-paired margin
  shifts are the proof the plan was applied.

## Why the Custodes lose with a plan when the Orks won with one

The Ork win came from routing 12"-move OC down layout-specific clear
corridors the formula doesn't know about — layout knowledge the formula
can't have. The Custodes have no such edge to encode: M5–6 with 11 units
means nobody reaches the y=30 objective line on move 1 regardless of
placement, so a fixed deployment mostly gives up the formula's one real
strength — counter-deploying reactively to the opponent's placements.
Locking 500 pts into deep strike (v1) made it worse: the arrival scorer
ignores earmarks and the board-presence deficit in rounds 1–2 cost more
than the flexibility bought. And v3 shows even *intents alone* can hurt:
a HOLD earmark is a standing +8.0 assignment bonus that pins a slow unit
to one objective all game, overriding the formula's dynamic reassignment
— rigidity is exactly what an 11-unit elite army cannot afford.

The finding worth keeping: **plan value is army-dependent.** Fast hordes
with corridor tricks gain from layout-tuned plans; slow elite armies with
few units are better served by the formula. Before spending hours
authoring, run one cheap probe (an earmarks-only or partial plan) through
the A/B and check the sign.

## Process notes (fed back into the playbook)

- The Plan Editor has its own army dropdown (`plan_editor_army_dropdown`);
  setting `player1_dropdown` loads the wrong army into the editor.
- The IntentPainterPanel spawns deferred after the last deployment — paint
  after a wait/refresh, use `get_node_or_null`, and read the saved JSON
  back to assert the earmark count before spending 30 minutes measuring.
- After a simulator run the scene stays on `Main`; return to the menu via
  `change_scene_to_file` before re-entering the editor.
- Run the A/A anchor before interpreting any single-arm number, and use
  seed-paired deltas against it — at sd 14–40 VP/game they are the only
  6-game comparison with any resolution.
