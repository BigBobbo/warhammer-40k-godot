# AI test cases

Positions where a human reviewed the AI's suggestion and recorded a verdict.

**Make one:** in any local game press **K**, read the "Why the AI suggests
this" card, optionally type a note, then click **Good call** or **Bad call**.
The game state and the suggestion are saved to
`<godot-userdata>/40k/ai_test_cases/` as a pair: `<id>.w40ksave` + `<id>.json`.

**Re-check:** `bash 40k/tests/run_ai_test_cases.sh` (or pass case paths).

| Verdict | PASS when | Use it to |
|---|---|---|
| good | the AI still makes the same choice | lock in behaviour you agree with |
| bad  | the AI now makes a different choice | track a flaw until a code change fixes it |

A "bad" case FAILS until the AI is fixed. That is expected: it is the to-do
list for AI work, and it turns PASS the moment a change fixes it.

**Compare two AI versions:** `bash 40k/tests/run_ai_test_cases.sh --compare main`
(any git ref). Every case runs on that version and on your working tree; the
report marks each case `=` (same choice) or `≠` (changed), shows both picks
with their top-scored options, and each version's PASS/FAIL. Use it after an AI
change to see exactly which reviewed positions it moved — including ones you
marked "good" that it should not have touched. The other version is checked out
into a temporary git worktree (first run imports the project: a few minutes).

**Commit a case:** copy both files of the pair into this folder.

Matching uses the action type, the unit/target ids, and which option the
first decision record picked (its key, else its board position, else its
description). See `40k/scripts/AISuggestionTestCases.gd`.
