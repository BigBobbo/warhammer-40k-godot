# Warhammer 40k 11th Edition — YouTube tactics/guide corpus

Research tooling that builds an index of 11th-edition tactics, guide, and
battle-report videos. Used as reference material when implementing core rules.

## Why not yt-dlp / the transcript APIs

Both are **bot-blocked from this container's cloud IP**. Measured, not assumed:

| Route | Result |
|---|---|
| `youtube-transcript-api` | `IpBlocked` immediately |
| `yt-dlp` | first request succeeded, every later one → "Sign in to confirm you're not a bot" |
| `WebFetch` on a watch URL | 302 → Google captcha |
| `/api/timedtext` direct | HTTP 200 but a ~1 KB stub (needs signed params) |

Two routes **do** work reliably and are what this tooling uses:

1. **Channel listing page** — `https://www.youtube.com/channel/<UC…>/videos`,
   parsed out of `ytInitialData` → `lockupViewModel` (~30 newest videos).
2. **Channel RSS feed** — `https://www.youtube.com/feeds/videos.xml?channel_id=<UC…>`
   (15 newest, with exact ISO publish dates and descriptions).

Search results pages parse the same way (~20 results/query), which is how
channels are discovered in the first place.

Note this gets **titles, dates, and metadata — not transcripts.** Transcript
text still requires cookies from a logged-in session or a non-cloud IP.

## Pipeline

```bash
python3 discover.py          # 32 search queries  -> search_videos.json, discovered_channels.json
python3 harvest_channels.py  # per-channel sweep  -> channel_videos.json
python3 classify.py          # gate + tag + merge -> final_videos.json
```

`index.html` is a self-contained browsable version (search, category filters,
channel filter, sort). Open it directly in a browser.

## Filtering

A video is kept only if it clears three gates:

- **Is 40k** — matches 40k/edition/faction/rules vocabulary.
- **Not another system** — Kill Team, AoS, Heresy, Necromunda, Konflikt '47, etc. rejected.
- **Not non-tactical** — painting, lore, unboxing, rumours, news/drama rejected.

Then it must land in at least one of eight categories: core rules, list building,
deployment/terrain, missions/scoring, phase tactics, faction/unit guides, battle
reports, meta/competitive.

Era filter: published on/after **2026-06-01** (11th ed release), *or* explicitly
titled "11th edition" — which is why some April–May 2026 pre-release coverage
is included on purpose.

## Coverage caveat

This is a broad sweep, **not a complete census**. Search returns ~20 results per
query and channel listings return ~30 recent videos, so prolific channels may
have older 11th-edition content that isn't captured, and channels that never
surfaced in any query are absent entirely. Tags are keyword-derived, so expect
occasional mislabels — spot-checking found and fixed several classes of false
positive, but the long tail isn't hand-verified.

## Current snapshot (harvested 2026-08-04)

- 1,054 videos across 91 channels, filtered from a 3,298-video pool
- Date range 2026-04-04 → 2026-08-04; 654 say "11th" in the title
- Meta/competitive 430 · battle reports 346 · list building 169 ·
  core rules 155 · deployment/terrain 152 · missions 134 · faction guides 108 ·
  phase tactics 52
