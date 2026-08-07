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
