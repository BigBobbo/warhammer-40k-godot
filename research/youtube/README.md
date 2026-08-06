# YouTube transcript mining → AI learnings

Turns a corpus of Warhammer 40,000 11th-edition YouTube transcripts into
evidence-backed, actionable changes for `40k/scripts/AIDecisionMaker.gd`.

## Provenance

`transcripts_text.jsonl.gz` — **gitignored** (19 MB). 1,029 transcripts,
10.5M words, 90 channels, 2026-04-04 → 2026-08-04 (68 records carry no `date`).
Gzipped JSONL, one object per line:

| field | notes |
|---|---|
| `video_id`, `title`, `channel`, `date`, `url` | as published |
| `cats` | one or more of Rules, Lists, Deployment, Missions, Phases, Factions, Batreps, Meta |
| `auto` | `true` for auto-generated captions — 1027 of 1029 |
| `words` | word count |
| `text` | caption text with per-minute `[MM:00]` markers |

Read it with `gzip.open(path, 'rt')`. **If the file is absent, stop and ask for
it** — every script here exits with an error rather than proceeding, and no
finding in `ai_learnings.json` may be written without a verifiable quote.

The captions are auto-generated, so proper nouns are frequently wrong
(`Orks`→`orcs`, `Waaagh!`→`wall`, `Votann`→`voltan`, `genestealer`→`genailer`).
Quotes in the outputs are **verbatim, errors included** — they are checked
mechanically against the corpus, so "fixing" them would break verification.

## Outputs

| file | what it is |
|---|---|
| `ai_learnings.json` | primary machine-readable output: 31 findings on two axes (decision × faction), each with evidence, rules status and a concrete AI change |
| `ai_learnings.html` | self-contained reader-facing page (no external CSS/JS/fonts), filterable on both axes, light + dark |
| `profiles/*.json` | draft AI profiles in the `ProfileManager` format — **drafts for review, not tuned values** |

## Scripts

```bash
# search: filtered / regex search with timestamps and deep links
python3 search_transcripts.py 'reactive move' --window 260 --limit 10
python3 search_transcripts.py 'oath of moment' --cat Factions --count-only

# compact batch scan — one line per hit, for finding signal fast
python3 mine.py THEME 'regex' --max 20
python3 batch.py screening          # named themed batches

# faction attribution and per-faction mining
python3 faction_index.py                       # transcript counts per faction
python3 faction_index.py --faction Orks        # which transcripts, and why
python3 faction_mine.py Orks 'waaa+gh.{0,80}'  # title-attributed pool only
python3 exact_quote.py <video_id> 'probe words'  # verbatim span + true timestamp

# build the outputs
python3 build_learnings.py     # -> ai_learnings.json
python3 build_profiles.py      # -> profiles/*.json
python3 build_html.py          # -> ai_learnings.html  (reads the JSON)

# gate: every quote must exist in the corpus at its cited timestamp
python3 verify_evidence.py
```

`verify_evidence.py` exits non-zero if any evidence quote is missing, is
attributed to the wrong channel, or sits more than two minutes from its cited
timestamp. Run it after editing `build_learnings.py`.

## Method notes

**Faction attribution.** A transcript counts toward a faction when the *title*
names it (human-written, so reliable) or the body carries ≥6 distinct alias
hits. Faction *findings* are drawn from the title-attributed pool only, unless
noted — one mis-hearable mention is never enough.

**Confidence.** `high` requires multiple independent channels stating the same
decision rule. Single-channel claims are `low` and do not get a profile; they
are listed under `gaps` instead.

**Rules status.** `confirmed` means checked against the 11e core rules
(<https://wahapedia.ru/wh40k11ed/the-rules/core-rules/>). `player_opinion` is
judgement rather than rules. `contradicts_rules` is a widespread misconception —
recorded as a finding, never taught to the AI.

**Staleness.** Faction balance moves with dataslates. ~92% of the corpus is
June–August 2026 and most of it post-dates the late-July balance pass, but each
finding's evidence carries dates so a stale claim can be spotted.
