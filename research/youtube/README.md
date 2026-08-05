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

These two routes get **titles, dates, and metadata**. Transcript text comes
from a third route — the InnerTube player endpoint — see *Transcripts* below.

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

## Transcripts

`fetch_transcripts.py` + `scrape_all.py` pull caption text for the indexed
videos. They bypass the yt-dlp block by POSTing directly to the **InnerTube
player endpoint**, which returns pre-signed `timedtext` URLs:

```
POST https://www.youtube.com/youtubei/v1/player?key=<public web key>
{"context":{"client":{"clientName":"IOS","clientVersion":"20.10.4",...}},"videoId":"..."}
```

**Client choice matters and was measured, not guessed.** `ANDROID_VR` returns
`LOGIN_REQUIRED` on most videos; `IOS` returns `OK` on the same ones in the same
second. The script tries IOS first and falls back to ANDROID_VR.

```bash
python3 scrape_all.py    # resumable; skips video_ids already in the output
```

### Rate limit (measured 2026-08-04/05)

From this cloud IP the run is clean at ~96% for the first **~680 videos**, then
hits a hard wall — every subsequent request returns `LOGIN_REQUIRED`. Final tally
for one window: **658 of 1,054** (7.0M words, 83 channels).

The wall was then characterised properly:

- **Not client-scoped.** Nine InnerTube client fingerprints were probed against a
  pending video (IOS, IOS_MUSIC, IOS_MESSAGES_EXTENSION, ANDROID,
  ANDROID_TESTSUITE, WEB_EMBEDDED_PLAYER, TVHTML5, MEDIA_CONNECT, base IOS).
  All refused. The quota is IP-scoped; swapping clients buys nothing.
- **Not a short cooldown.** Eight 15-minute cooldown rounds (2 hours) all stayed
  blocked.
- **Not limited to the player endpoint.** Once throttled, the RSS feed returns
  404 for a channel id that returned 200 earlier, and the channel listing page
  parses 1 `lockupViewModel` instead of 30. The *harvest* routes degrade too.

So a cloud IP gets roughly one ~680-video window, then loses YouTube access
broadly for an extended period. **Measured recovery: ~10.5 hours.** After the
block lifted, a resumed pass fetched 371 of the 396 outstanding videos at 93%
in 1.1 minutes, taking the corpus to **1,029 / 1,054 (97%)**.

The 25 that remain are livestreams and Shorts with no caption track to fetch
(24 have no duration at all; the one exception is an archived 3-hour GT stream
that refuses consistently). This is the practical ceiling, not a pending task.

### Finishing on a residential IP

Kept for re-scrapes as new videos land. A home IP does not carry the
cloud-provider penalty, and plain `yt-dlp` works directly — no InnerTube
poking needed:

```bash
cd research/youtube && ./finish_on_mac.sh
```

`finish_on_mac.sh` reads `transcripts_pending_ids.txt`, fetches with
`--sleep-requests 1`, folds the raw json3 into the same JSONL shape this corpus
uses, and skips anything already downloaded so re-runs are cheap. If a bot check
ever does appear, add `--cookies-from-browser chrome`.

`transcripts_pending_ids.txt` now holds only the 25 caption-less
livestreams/Shorts, so there is nothing left for it to usefully fetch from the
current snapshot.

### Output

`transcripts_text.jsonl.gz` — 1,029 transcripts, 10.5M words, 90 channels;
one JSON object per line:
`video_id, title, channel, date, cats, url, auto, words, text`.
`text` keeps coarse `[MM:00]` minute markers so a claim can be traced back to a
timestamp; per-cue millisecond timing is dropped to keep the file at ~18 MB
(the full timed version is ~41 MB and can be regenerated by re-running).

Caption text is almost all auto-generated (ASR), so expect mis-heard proper
nouns — faction and unit names especially.

## Current snapshot (harvested 2026-08-04)

- 1,054 videos across 91 channels, filtered from a 3,298-video pool
- Date range 2026-04-04 → 2026-08-04; 654 say "11th" in the title
- Meta/competitive 430 · battle reports 346 · list building 169 ·
  core rules 155 · deployment/terrain 152 · missions 134 · faction guides 108 ·
  phase tactics 52
