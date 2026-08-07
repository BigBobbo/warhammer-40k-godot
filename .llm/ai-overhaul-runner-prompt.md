# Runner prompt — autonomous execution of the AI overhaul task list

*Paste everything below the rule into a fresh Claude Code session on this repo to work
through `.llm/ai-overhaul-todo.md` unattended. The prompt is resumable: state lives in the
todo file's checkboxes/evidence blocks, `.llm/ai-overhaul-progress.md`, and pushed commits,
so re-running the same prompt in a new session continues instead of restarting.*

---

Work through .llm/ai-overhaul-todo.md and complete every task in it, autonomously, end to end.
I am away from my computer: never ask me anything, never wait for confirmation, never end your
turn while workable tasks remain. A task is never "too large" — it can only be decomposed
further and then done. Run until every task is either completed-and-validated or carries a
documented, reproduced blocker.

RESUME RULE (also applies to a fresh start): first read .llm/ai-overhaul-progress.md (if it
exists) and the checkboxes in the todo file, then continue from the first incomplete task.
Never redo completed work; never trust a checkbox that has no evidence block under it —
re-verify those.

SETUP
- Read in full before any work: .llm/ai-overhaul-todo.md (the guardrails preamble is binding),
  tools/ai_lab/README.md, and docs/AI_CURRENT_AND_FUTURE.html Part III.
- Environment: export PATH="$HOME/bin:$PATH"; run `godot --headless --import` once. Benchmarks
  run headless. Windowed scenarios and screenshots DO work in this container via the xvfb godot
  shim and the MCP bridge on 127.0.0.1:9080 — see CLAUDE.md "You CAN run the game AND
  screenshot the UI". Do not claim a tool limitation without a reproduced failing command and
  its exact output.
- Git: create your working branch from latest origin/main. Push after every task. Do not open
  or merge PRs — I will review the branch when I return.

ORDER
Follow the phase table at the bottom of the todo file (Phase 1 → 5), tasks in listed order
within a phase, respecting each task's Depends line. You are a single session, so Lock tags
never conflict. Long self-play campaigns (B3, E1, anything over ~30 minutes of games) must run
in the background (they are resumable — run_lanes skips finished seeds, cem_driver checkpoints
each generation); while they run, work the next task that does not depend on their results.
Never idle waiting on games while independent work exists.

PER-TASK LOOP — strictly, for every task
1. Re-read the task. Verify every premise against the code; line numbers drift, function names
   are the anchor. If a premise is stale, fix the task text in the same commit and adapt.
2. Implement completely. No stubs, no placeholders, no "simplified version for now". If an
   approach stalls, change approach, not scope.
3. Validate for real: execute every Tier A bullet as an actual command and capture actual
   output. If a Tier A bullet cannot be executed, the work is not done — make the state
   observable and rerun. Never fabricate, predict, or paraphrase results you did not run.
4. Tier B is a human check: perform it yourself honestly and record the assessment as a dated
   note "Tier B self-assessed — pending human spot-check". Then mark the checkbox [x].
5. Append a dated evidence block under the task: commands run, key numbers (for evaluator work,
   E ± SE and games count), files touched.
6. Commit (message references the task id) and push before starting the next task — the
   container is ephemeral and unpushed work can vanish.
7. Update .llm/ai-overhaul-progress.md (create on first task): one line per task — status,
   key result, timestamp.

GATES YOU MAY NEVER SKIP
- "Behavior-preserving" requires tools/ai_lab/determinism_check.py byte-identical action
  streams before vs after, both mirror fixtures, at least 2 seeds each. No exceptions.
- Behavior changes go through tools/ai_lab/run_paired.py with the stopping rule recorded
  before the first game, judged by the acceptance thresholds for their change class in the
  todo preamble (+4 VP at 2 SE for tuned candidates; exam-flip plus >= -1 VP at 1 SE
  non-regression for structural changes).
- Every new fixture passes tools/ai_lab/fixture_check.py before its first game.
- Statistical work defaults to the Custodes mirror (~10x cheaper); use the Ork mirror only
  where melee coverage is the point (B3, D4).
- Player-facing tasks (E5, F1, F2, F3): windowed scenario + in-game screenshot + a
  40k/data/version_history.json entry, per CLAUDE.md.

OUTCOMES THAT COUNT AS COMPLETION — handle and continue, do not stop
- A kill criterion fires -> execute its documented off-ramp (write-up, default-off parameter,
  park), record the measured numbers, mark the task done with that outcome.
- The evaluator returns null or negative -> the honest write-up IS the deliverable (E1 says so
  explicitly: "ship or null — either outcome is the deliverable").
- A task assumes a resource you lack (e.g. an external API key for E2/E3's proposer) -> build
  the pluggable interface as specced, act as the proposer yourself for the validation cycle,
  and record the substitution in the task notes.

BLOCKED != STOPPED
If a task is genuinely blocked, record the exact failing command and output under it, mark it
"BLOCKED — <reason>", move to the next workable task, and retry every blocked task once at the
end of the run. Never halt the run for one task. Never ask me anything. Do not stop because
the session is long — context compaction is handled by the harness; the journal, the todo
file, and pushed commits carry all state.

FINISH LINE
When every task is done or documented-blocked: write a final summary at the top of the
progress journal — tasks completed, measured deltas (E ± SE per shipped change), exam-suite
pass count before vs after, blocked tasks with reasons, and the three highest-value next
actions — commit, push, and only then end.
