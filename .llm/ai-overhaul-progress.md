# AI Overhaul — progress journal

Companion to `.llm/ai-overhaul-todo.md`. One line per task: status, key
result, timestamp. Evidence blocks live under each task in the todo file;
this file is the index.

Run started 2026-08-07 on branch `claude/ai-overhaul-todo-completion-ve8fhj`
(from `origin/main` @ `8d693c7`).

## Standing environment notes

- 4 cores / 15 GB RAM. 3 lanes is the documented maximum (`cores - 1`); at 2
  lanes a Custodes mirror game is ~62-76 s, Ork ~8 min.
- A pristine `git worktree` of the base commit lives in the session
  scratchpad (`scratchpad/base`) so reference "before" seasons can be played
  while the working tree is being edited. Reference seasons at `8d693c7`:
  `scratchpad/seasons/ref_cust_HEAD`, `scratchpad/seasons/ref_ork_HEAD`
  (seeds 5001-5002, arm `ref`, Hard). Behaviour-preserving tasks compare
  against these rather than replaying the "before" arm each time.
- `determinism_check.py` gained a `--require {all,trajectory,outcome}` flag.
  Default stays `all`. `trajectory` is the correct gate for an
  *instrumentation* task, whose claim is "richer records, identical game" —
  the decisions column is still printed either way, so nothing is hidden.

## Task status

| Task | Status | Key result | When |
|---|---|---|---|
| A1 | DONE | shooting records carry real alternatives; hold_fire recorded both ways; trajectory-identical both mirrors | 2026-08-07 |
| A2 | DONE | movement score decomposed: named-terms 0/803 -> 797/803, census terms 12 -> 36 | 2026-08-07 |
| A3 | DONE | parameters_used drained from get_param: 5 -> 105 distinct params in records; validator PASS | 2026-08-07 |
| A4 | DONE | 50 reserves/embark/disembark coefficients promoted; unreachable 78% -> 62%; null test E=0.00+/-0.00 | 2026-08-07 |
| A5 | DONE | 59 fight/charge/deployment coefficients promoted; unreachable 62% -> 42%; null test E=0.00 | 2026-08-07 |
| D1 | DONE | combat-math oracle shipped; melee wound-overflow cap fixed (3.0x error) and measured neutral (pooled E=-0.74+/-0.75); 92 divergences catalogued as a ratchet, owned by new task D1b | 2026-08-07 |
| A7 | DONE | .github/workflows/ai-lab.yml + ratchet_check.py; red/green verified by exit code; NOT yet observed on a GitHub runner | 2026-08-07 |
| B4 | DONE | 12 exams authored, 10 gate and pass in ~300s, 2 moved to aspirational/ owned by D3 and D4; verdicts deterministic across two runs | 2026-08-07 |
| D1b | NEW | split out of D1: close the catalogued melee-keyword and ranged over-prediction classes | 2026-08-07 |
| B2 | DONE | asym_orks_vs_custodes_postdeploy built + fixture_check PASS; A/A F=-11.30+/-2.54 over 20 games, 0 stalls | 2026-08-07 |
| A6 | PARTIAL | 6 new decision types emitted, determinism-clean; only secondary_discard verified live — no fixture drives formations/deployment (split out as A6b) | 2026-08-07 |
| A6b | NEW | build a pre-deployment benchmark fixture so A6's other five types can be verified | 2026-08-07 |
| B0 | DONE | 238-parameter frozen profile + vs_baseline.py (selftest E=0.00); A/A F measured on all three fixtures, 50 games, 0 stalls | 2026-08-08 |
| B1 | PARTIAL | premise disproved by measurement: time_scale 6->120 does not move wall clock, so pacing is NOT the cost. Fixed overhead ~15s/game, AI compute ~115ms/action. --bench-unpaced deliberately not shipped | 2026-08-08 |
