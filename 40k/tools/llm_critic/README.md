# LLM critic — an LLM reviews the AI's suggestions

The LLM does **not** pick moves (legality stays with the engine). It reads what
the AI suggests at sampled decision points — chosen option, rejected options,
every score term, the AI's own reasoning lines, the board and datasheets — and
judges whether the *logic* is flawed. It sees what a player sees: two
screenshots per decision (whole board + close-up, with the K card's
suggestion overlay drawn), every terrain piece, and engine-computed line of
sight from the acting unit to each enemy. A second pass reads the AI source and
groups the flags into root causes with proposed code changes. **A human
validates every proposal before anything changes.**

```
critic.py collect   AI-vs-AI game (PlanSimulator, Competitive, seeded)
   │  at sampled decision points: freeze (time_scale 0) →
   │  AIPlayer.request_suggestion() (same call as the K card, pure preview) →
   │  capture.gd (options + score terms + reasoning + LoS, saves the position
   │  + a pending AI test case) + snapshot.gd (board) + shot_prep.gd (overlay,
   │  HUD hidden) → 2 screenshots → shot_restore.gd → unfreeze
   │  once per game: roster.gd (datasheets), terrain.gd (terrain in inches)
critic.py review    claude -p per decision → verdict JSON (sound/questionable/flawed)
critic.py synthesize claude -p over the flags, read-only access to the AI source
   │  → proposals.md: root causes, file/term, proposed change, how to verify
critic.py verify    (close the game first) reload each flagged position in a
                    fresh game; mark whether the AI still suggests the same thing
critic.py report    REPORT.html (validation page, below) + REPORT.md; flagged positions → "llm_critic_<case>" in the
                    in-game Load menu, flawed cases get verdict "bad" + the note
critic.py promote   (after YOU agree) copy case pairs into tests/ai_cases/
                    --from-verdicts <file>: use what you marked in REPORT.html
```

## Run

Game running windowed with the MCP bridge (see CLAUDE.md), `claude` CLI on PATH.

```bash
cd 40k/tools/llm_critic
python3 critic.py all --seeds 7001 --label first_look            # full pipeline
python3 critic.py all --seeds 7001-7003 --seat 1 --max-round 3    # P1 only
python3 critic.py collect --army1 custodes_lions --army2 custodes_lions --phases MOVEMENT,SHOOTING
python3 critic.py review runs/<run> --fresh --review-model claude-opus-5-5
python3 critic.py verify runs/<run>          # game closed; marks Repro in REPORT.md
python3 critic.py report runs/<run>
python3 critic.py promote runs/<run> s7001_r2_p1_shooting_1
```

Output per run: `runs/<stamp>_<label>/` (gitignored) — `bundles.jsonl`
(captured decisions), `reviews.jsonl`, `proposals.md`, `REPORT.md`. Position
saves + case JSONs live in `<godot-userdata>/40k/llm_critic/<run>/`, outside
`ai_test_cases/`, so unreviewed cases never enter `run_ai_test_cases.sh`.

## Validating (the human step)

`REPORT.html` is one self-contained page (screenshots embedded): the grouped
proposals, then a card per decision — both screenshots (click to enlarge),
what the AI suggested, the reviewer's verdict / logic flaw / proposed fix,
the options with their score terms, the AI's reasoning, line of sight. Under
each card mark **the AI's decision was good / bad** and **the reviewer was
right / wrong** (+ a note). Answers stay in your browser; **Export verdicts**
downloads them, then:

```bash
python3 critic.py promote runs/<run> --from-verdicts ~/Downloads/verdicts_<run>.json
```

promotes every decision you called good/bad to `tests/ai_cases/` with your
verdict and note, and prints the reviewer's accuracy by your judgement — the
number to watch when tuning the reviewer prompt.

Manual route:

1. Read `REPORT.md` — proposals first, then per-decision reviews.
2. Only cases with Repro = yes are worth promoting: some in-phase state
   (shooting order, reserve tie-breaks) is not in a save, so a few positions
   ask a different question on reload.
3. In-game: **Load** → `llm_critic_<case>` → press **K**. Is the critic right?
4. Agree → `critic.py promote runs/<run> <case>`. The case is "bad": it FAILS
   in `bash 40k/tests/run_ai_test_cases.sh` until an AI change makes a
   different choice, then PASSES — the fix's acceptance test.
5. Implement the proposal; re-run the promoted cases (and `--compare main`)
   to see what else moved.

## Knobs

| Flag | Default | |
|---|---|---|
| `--phases` | MOVEMENT,SHOOTING,CHARGE,FIGHT | also COMMAND, DEPLOYMENT, FORMATIONS |
| `--per-phase` / `--stride` | 2 / 2 | captures per player-phase; AI actions between them |
| `--max-captures` / `--max-round` | 40 / 5 | per game |
| `--time-scale` | 2.0 | higher = fewer catchable mid-phase points |
| `--review-model` / `--synth-model` | sonnet-5-5 / opus-5-5 | |
| `--jobs` | 4 | parallel reviews |
| `--no-shots` | off | skip screenshots |

## Known limits (v1)

- Positions are saved with the deciding seat as HUMAN (the K-card situation),
  so the AI does not act on reload before you or the checker can ask it.
- Decisions with fewer than two scored options are skipped (nothing to judge).
- LoS is from the acting unit only, to each enemy unit, at its current
  position (not from a move's destination) — the screenshots cover the rest.
- Both armies of a mirror match look alike in the screenshots; the reviewer
  is told to tell sides apart with the board JSON coordinates.
- `--no-shots` skips screenshots (faster, blind reviewer).
- Reviewer verdicts are opinions; expect some false positives. That is why the
  synthesis step may reject flags and why promotion is manual.
- `orks` (Ghazghkull list) currently stalls AI-vs-AI at Formations
  ("Ghazghkull Thraka has Supreme Commander and must be your Warlord"); use
  another army until that is fixed.
