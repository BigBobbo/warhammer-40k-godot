# Dev Blog Production Plan — Complete Execution Roadmap

*Master plan for maximum reach and engagement. March 2026.*

**Related documents created this session:**
- [`DEV_BLOG_CONTENT_OUTLINE.md`](DEV_BLOG_CONTENT_OUTLINE.md) — Full narrative arc, episode breakdowns, visual asset lists, commit-by-commit story
- [`VIDEO_PRODUCTION_RESEARCH.md`](VIDEO_PRODUCTION_RESEARCH.md) — Tool recommendations, format analysis, thumbnail data, AI coding landscape, competitive positioning

---

## Table of Contents

1. [Pre-Production Phase (Weeks 1-2)](#phase-1-pre-production-weeks-1-2)
2. [Production Phase (Weeks 3-4)](#phase-2-production-weeks-3-4)
3. [Post-Production Phase (Weeks 5-6)](#phase-3-post-production-weeks-5-6)
4. [YouTube Algorithm Optimization](#phase-4-youtube-algorithm-optimization)
5. [Social Media Strategy](#phase-5-social-media-strategy)
6. [Launch Sequence](#phase-6-launch-sequence)
7. [Ongoing Content Calendar](#phase-7-ongoing-content-calendar)

---

## Phase 1: Pre-Production (Weeks 1-2)

### 1.1 IP Rebrand (CRITICAL — Do First)

Before recording anything, rebrand to avoid Games Workshop IP issues. The story is "I built a complex tabletop strategy game" — the specific IP doesn't matter to the narrative.

| Task | Details | Priority |
|------|---------|----------|
| Rename factions | Space Marines → original name, Orks → original name | P0 |
| Rename units | Intercessors, Boyz, etc. → original names | P0 |
| Remove GW lore references | Any lore text, flavor text | P0 |
| Create original game title | Short, memorable, searchable | P0 |
| Update UI/menus with new names | All in-game text | P0 |
| Keep all mechanics | Phase structure, weapon keywords, scoring — these are game mechanics, not IP | — |

**Why this is P0:** One DMCA from Games Workshop kills the entire channel before it starts. Do this before recording a single frame.

### 1.2 Tool Setup

**Free Starter Stack (total cost: $0 + mic):**

| Tool | Purpose | Setup Time |
|------|---------|------------|
| **OBS Studio** | Screen recording (game footage + terminal) | 1 hour |
| **DaVinci Resolve Free** | Video editing, color grading, audio | 2 hours |
| **Manim** (Python) or **Flourish** | Commit timeline animation (the hero visual) | 3 hours |
| **Canva** (free tier) | Thumbnails | 30 min |
| **Audacity** | Voiceover recording + editing | 30 min |
| **YouTube Audio Library** | Background music (zero copyright risk) | — |

**Mic recommendation:** Samson Q2U (~$70) or Audio-Technica AT2020USB+ (~$100). A decent mic is the single highest-ROI equipment purchase.

**Optional upgrades:**
- Epidemic Sound ($9.99/mo) — better music library, clears Content ID claims
- TubeBuddy or VidIQ (free tiers) — SEO optimization, A/B testing, analytics

### 1.3 Channel Setup

| Task | Details |
|------|---------|
| Create YouTube channel | Use a memorable, searchable name related to your game or dev identity |
| Channel banner | Dark theme, game screenshot, consistent with thumbnail style |
| Channel description | Keywords: indie game dev, AI coding, strategy game, tabletop, solo developer |
| About section | Brief story + links to game |
| Channel trailer | Use a 60-second version of the hero video hook (make after hero video) |
| Custom URL | Claim after 100 subscribers |
| Enable all monetization prerequisites | Verify phone, enable community tab when available |

### 1.4 Record Raw Footage

See [`DEV_BLOG_CONTENT_OUTLINE.md`](DEV_BLOG_CONTENT_OUTLINE.md) for the complete visual asset list. Priority recordings:

**Must-have (hero video):**
- [ ] Clean full-game playthrough (Deployment → Scoring, ~5 rounds)
- [ ] AI vs AI match at Competitive difficulty
- [ ] Side-by-side: Easy AI vs Competitive AI on same scenario
- [ ] Early gameplay footage from Aug/Sep (recreate the janky prototype look if needed)
- [ ] Feb gameplay footage (the polished version) — for before/after split
- [ ] The commit graph on GitHub (show the exponential curve, scroll through it)
- [ ] Code scrolling through large files (show the scale visually)
- [ ] Claude Code terminal sessions (the human-AI interaction loop)
- [ ] Test suite running (2,500+ tests passing)

**Nice-to-have (episodes):**
- [ ] PR creation and merge workflow
- [ ] Bug reproduction → fix cycle
- [ ] An audit session: Claude reading rules and filing gaps
- [ ] AI thinking overlay close-ups
- [ ] Dice roll animations, charge arrows, movement paths

### 1.5 Create the Hero Visual: Commit Timeline Chart

This is **the single most important visual asset**. It tells the entire story in one image.

**Tool options (ranked):**
1. **Flourish** (free) — No-code animated charts. Racing bar charts, time sliders. Export as video or GIF.
2. **Manim** (free, Python) — Script-driven, precise control. Export frames → composite in DaVinci.
3. **D3.js** — If you want an interactive version for the website.

**Chart specifications:**
- X-axis: Date (Aug 2025 → Mar 2026)
- Y-axis: Cumulative commits
- Annotations: "Solo coding", "Hibernation", "AI enters", "160 commits/day"
- Animation: Slow accumulation, then dramatic vertical acceleration
- Color: Dark background, neon accent on the hockey stick portion

**This chart should appear in:**
- Hero video opening (animated)
- Thumbnail (static frame)
- Every social media post (static image)
- Blog post header (animated GIF)

---

## Phase 2: Production (Weeks 3-4)

### 2.1 Hero Video Script

Target: **15-18 minutes** (the sweet spot for engagement + algorithm).

**Structure** (see [`DEV_BLOG_CONTENT_OUTLINE.md`](DEV_BLOG_CONTENT_OUTLINE.md) for full detail):

| Segment | Duration | Content |
|---------|----------|---------|
| **Cold open** | 0:00-0:30 | Commit graph animation: flat → explosion. "What happened?" |
| **The pitch** | 0:30-1:30 | Stats flash: 1,067 commits, 190K lines, 2,500 tests. "This is the story of what happens when a solo dev gets AI superpowers." |
| **Act 1: The Solo Grind** | 1:30-5:00 | Aug–Oct. 1 commit/day. Building foundations. Relatable struggle. Early footage. |
| **Act 2: The Return** | 5:00-8:00 | Feb comeback. Infrastructure. Then AI enters. 38 commits in one day. The graph bends. |
| **Act 3: The Supernova** | 8:00-12:00 | 552 commits in 5 days. 160-commit day. Features landing faster than review. AI vs AI showcase. |
| **The Reflection** | 12:00-15:00 | What worked (human foundation + AI acceleration). What didn't (monolith problem, sync bugs). What it means. |
| **CTA + Next** | 15:00-15:30 | Subscribe, episode series teaser, link to play the game |

**Script writing tips:**
- Write the voiceover script first, then plan visuals to match
- Every sentence should either advance the story or deliver a data point
- Cut any segment where you're explaining without showing
- Read aloud and time it — aim for 150-180 wpm (conversational pace)

### 2.2 Record Voiceover

- Record in a quiet room (closet with clothes = cheap sound dampening)
- Use Audacity: noise reduction → compression → normalization
- Record each section separately for easier editing
- Re-record any section that sounds flat or rushed — energy matters

### 2.3 Shorts Production

**Create 5-8 Shorts from hero video content** (critical for discovery — see Algorithm section):

| Short | Content | Hook |
|-------|---------|------|
| **Short 1** | The commit graph animation (15 sec) | "What 1,067 commits looks like" |
| **Short 2** | Before/after gameplay split (30 sec) | "6 months of game dev in 30 seconds" |
| **Short 3** | 160-commit day timelapse (45 sec) | "I made 160 commits in one day" |
| **Short 4** | AI vs AI playing a match (30 sec) | "When two AIs play a strategy game" |
| **Short 5** | The debugging struggle (30 sec) | "When AI writes code that doesn't work" |
| **Short 6** | Stats reveal (15 sec) | "190,000 lines of code. One developer. How?" |
| **Short 7** | Terminal session timelapse (45 sec) | "What coding with AI actually looks like" |
| **Short 8** | The 90x acceleration stat (20 sec) | "From 1 commit/day to 110 commits/day" |

**Shorts specs:**
- 9:16 vertical, under 60 seconds (50-60 sec optimal, 76% watch-through)
- Hook in first 3 seconds or viewers swipe
- Add "#Shorts" in title and description
- Publish 1-2 per day starting 3-5 days before hero video launch

---

## Phase 3: Post-Production (Weeks 5-6)

### 3.1 Editing the Hero Video

**DaVinci Resolve workflow:**

1. **Import all footage** — organize into bins: gameplay, terminal, GitHub, charts, B-roll
2. **Lay down voiceover** — this is the timeline spine
3. **Cut visuals to voiceover** — match what you're saying to what viewers see
4. **Pacing rules:**
   - Fast cuts (10-15 sec) during explanation segments
   - Longer holds (20-40 sec) for impressive visuals (AI gameplay, chart reveals)
   - Change music when the story shifts (Act 1 → Act 2 → Act 3)
   - Drop volume / go silent before major reveals
5. **Add overlays:**
   - Stats text (bold sans-serif, 1-3 words max)
   - Code snippets (JetBrains Mono, dark warm background)
   - Commit messages scrolling
   - Chapter markers
6. **Color grade:** Dark, warm tones. Not cold blue, not pure black.
7. **Audio mix:** Voiceover -3dB, music -18dB under voice, SFX -12dB

### 3.2 Thumbnail Creation

**Primary thumbnail concept: Before/After Split Screen**
- Left half: Janky August prototype (desaturated, slightly blurred)
- Right half: Polished February game (vibrant, crisp)
- Text: **"6 MONTHS → 2 WEEKS"** (bold white, black outline)
- Dark charcoal background with neon cyan/magenta edge glow
- Commit graph hockey stick silhouette in background (subtle)

**Data-backed specs:**
- 1280x720px (16:9), under 2MB, PNG
- Design at 1280x760 to account for YouTube's duration overlay
- Test at 160x90px (mobile preview size) — if text is unreadable, simplify
- Before/after split = **+35% CTR** vs single-image thumbnails
- Dark + neon glow = **+30% CTR** vs low-contrast
- Consistent style across all videos = **+15% retention**

**Create 3-4 variants and use YouTube's Test & Compare feature to A/B test.**

**Alternative thumbnail concepts:**
1. The commit graph hockey stick curve + "WHAT HAPPENED?" text
2. Terminal with AI code + game screenshot overlay + "1,067 COMMITS"
3. Game board close-up with AI annotations visible + "AI BUILT THIS"

### 3.3 Chapters & End Screens

**Chapters** (add timestamps in description — improves SEO and viewer navigation):
```
0:00 The Moment Everything Changed
0:30 The Stats
1:30 Act 1: The Solo Grind (Aug-Oct 2025)
5:00 Act 2: The Return (Feb 2026)
8:00 Act 3: The Supernova (552 Commits in 5 Days)
12:00 What Worked and What Didn't
15:00 What This Means for Solo Devs
```

**End screen** (last 20 seconds):
- Subscribe button
- Link to Episode 1
- Link to play the game

---

## Phase 4: YouTube Algorithm Optimization

### 4.1 How the Algorithm Works in 2026

The YouTube algorithm is not one system — it's five: **Browse**, **Suggested**, **Shorts**, **Search**, and **Notifications**. Key changes in 2026:

**The Gemini AI integration (January 2026) — the biggest architectural change in years:**
- **Semantic IDs:** Gemini assigns semantic meaning to videos — understanding context, intent, emotional state, pacing, and tone. Not just metadata anymore.
- **Frame-by-frame analysis:** The algorithm literally "watches" your video, listens to spoken words, reads on-screen text
- **Cross-platform awareness:** Gemini connects Google Search queries, Gmail activity, Drive docs to predict what users want. Someone researching tabletop wargame rules in Google may see your devlog even if they've never watched game dev content.
- **"Good Abandonment":** If a viewer clicks away from a tutorial after 2 minutes because they found what they needed, Gemini recognizes that as success (old algorithm counted it as failure).
- **Channel Semantic Profiles:** Gemini builds a profile of your channel's value delivery. **Your packaging must match your delivery** — channels that consistently match promises to content get preferential distribution.
- **Two algorithms running simultaneously:** Gemini works alongside the original system, not replacing it.
- Properly disclosed AI content is NOT penalized (important for your content)

**What the algorithm rewards:**
1. **Viewer satisfaction** (measured via surveys) > pure watch time
2. **High retention rate** — 50-60%+ is good, 70%+ is strong, 80%+ is exceptional
3. **Click-through rate** — 4-10% is average, above 10% is excellent
4. **Engagement** — comments, likes, shares, saves
5. **Repeat viewing** within a topic — series viewers binge = strong signal
6. **Session time** — videos that lead to more watching (not leaving YouTube)

**Good news for new channels (the 2026 algorithm favors you):**
- The algorithm now tests new creators more aggressively when early signals are strong
- A new video with strong CTR + retention can get broader testing within **days, not weeks**
- The "Hype" feature lets fans boost videos from channels under 500K subscribers
- YouTube's Test & Compare lets you A/B test **up to 3 thumbnails AND titles** natively (title testing rolled out globally December 2025)
- Small channels can outrank big channels in search if they better satisfy the query
- **The Gemini integration is particularly good for niche channels:** A well-made video about "building tabletop wargame movement mechanics in Godot with Claude Code" will be semantically matched to the exact right audience — people who care about wargaming, Godot, AI coding, or strategy game dev — even without perfect keyword optimization
- Over **70% of all watch time** comes from algorithmic recommendations, not search or subscriptions

### 4.2 SEO Optimization

**Title formula:**
```
[Emotional hook] + [Specific detail] + [Time element]
```

**Primary title options (under 60 characters, keyword-front-loaded):**
1. `AI Coding Turned My Solo Game Into 190,000 Lines of Code`
2. `1,067 Commits: Solo Dev + AI Built a Strategy Game`
3. `From 1 Commit/Day to 160: How AI Changed My Game`
4. `6 Months Solo. Then AI Did This to My Game.`

Use YouTube Studio's A/B testing — creators who test titles see **15-25% CTR improvement** within 30 days.

**Description (first 200 chars are critical — shown "above the fold"):**
```
I spent 6 months building a tabletop strategy game solo in Godot.
100 commits in 5 months. Then I plugged in AI coding tools.
960 commits in 3 weeks. This is what happened.

[Full description with chapters, links, keywords below]
```

**Description body should include:**
- All chapter timestamps
- Semantic keywords woven naturally: "AI game development", "Claude Code", "Godot engine", "indie game dev", "solo developer", "strategy game", "vibe coding"
- Links: game, GitHub (if public), social profiles
- Brief paragraph summarizing the video (for AI search engines — Google AI Overviews, ChatGPT, Perplexity all use descriptions)

**Tags (8-12, declining importance but still useful):**
```
AI coding, AI game development, Claude Code, vibe coding, Godot engine,
strategy game, indie game dev, solo game dev, tabletop game, game dev diary,
coding with AI, AI programming
```

**Hashtags (2-3 in description):**
```
#indiegamedev #AIcoding #godot
```

### 4.3 Posting Strategy

**Optimal schedule for gaming/tech crossover:**
- **Long-form:** Wednesday–Friday, 3-5 PM local time (schedule 1 hour before peak)
- **Shorts:** Daily, 12-2 PM (midday engagement window)
- **Frequency:** 1 long-form per week + 3-5 Shorts per week
- **Consistency** matters more than frequency — pick a day and stick to it

**The 3x/week growth data:**
- 3 uploads/week = 8x faster view growth, 3x faster subscriber growth vs <1/month
- But quality > quantity — if 3/week drops quality, do 1/week well
- Shorts + long-form channels grow **41% faster** than single-format channels

### 4.4 Retention Optimization

**The first 30 seconds decide everything.** Below 50% retention at 10-15 seconds = broken hook.

**Your hook strategy (per research):**
1. Open with the commit graph animation (visual spectacle — stops the scroll)
2. Immediately establish stakes: "1,067 commits. 190,000 lines. One developer."
3. Create curiosity gap: "What happened?" before the graph goes vertical
4. Deliver payoff fast: show the game within 30 seconds

**Retention tactics throughout:**
- **Progress loop every 2-3 min:** Reference the original goal visually
- **Music changes:** New track for each Act
- **Pattern interrupts:** Switch between gameplay, terminal, charts, talking head
- **Micro-hooks:** "But then something unexpected happened..." before each Act transition
- **55% of viewers drop in the first 60 seconds** — front-load the most impressive content

### 4.5 Engagement Signals (Ranked by Importance)

| Rank | Signal | Why | Benchmark |
|------|--------|-----|-----------|
| 1 | **Watch time / Retention** | Foundational signal. Below 40% = deprioritized | 50%+ good, 70%+ excellent |
| 2 | **Comments** | Most heavily weighted — requires viewer investment | Active sections get recommended more |
| 3 | **CTR** | Critical for initial distribution | 4-6% avg, 7%+ strong |
| 4 | **Likes** | Strong algorithmic signal | 4-5% like rate is healthy |
| 5 | **Satisfaction surveys** | Growing importance post-Gemini | Can't measure directly |
| 6 | **Shares** | Valuable but less weighted than on TikTok | Increases off-platform reach |
| 7 | **Subscribes from video** | Signals long-term value | — |

**How to boost engagement:**
- Simple CTAs increase engagement by **50%** — but ask specific questions ("What faction should I implement next?") not generic ones ("leave a comment")
- Reply to **every comment** in your first 6 months — the algorithm tracks comment section activity
- Pin a comment with a question or poll
- Use community posts (polls, updates) between videos

### 4.6 AI Content Disclosure

YouTube requires creators to label AI-generated or significantly AI-altered content. Since your game was coded with AI assistance (Claude Code), you should:
- Disclose AI usage transparently (this is your CONTENT, not something to hide)
- Label appropriately in YouTube Studio's AI disclosure settings
- Frame it positively: "built with AI tools" not "generated by AI"
- Properly labeled AI content receives normal algorithmic distribution
- Undisclosed AI content that YouTube detects → reduced recommendations

---

## Phase 5: Social Media Strategy

### 5.1 Platform Priority (Ranked)

| Priority | Platform | Purpose | Audience Size |
|----------|----------|---------|---------------|
| 1 | **YouTube** | Primary content hub | 2.5B monthly users |
| 2 | **Reddit** | Community engagement + viral potential | Multiple subs, millions of members |
| 3 | **Twitter/X** | Dev community + journalists + real-time discussion | Large dev community |
| 4 | **TikTok** | Short-form discovery (declining organic reach) | 1.59B users |
| 5 | **Hacker News** | Tech audience, high-quality traffic, viral potential | ~500K daily readers |
| 6 | **Discord** | Community building, direct engagement | Growing |
| 7 | **itch.io** | Game distribution + built-in community | Indie game audience |

### 5.2 Reddit Strategy

Reddit is your **highest-leverage social platform** after YouTube. The Warhammer + gamedev + AI coding communities are massive and engaged.

**Target subreddits:**

| Subreddit | Members | Strategy |
|-----------|---------|----------|
| **r/Warhammer40k** | 1.4M | Post AFTER rebrand. Frame as "tabletop-inspired strategy game." Show gameplay, ask for feedback. DO NOT mention the original IP. |
| **r/gamedev** | 1.5M+ | Devlog format. "I built a turn-based strategy game with AI coding tools." Show the commit timeline chart. |
| **r/indiegaming** | 500K+ | Gameplay GIFs/clips. Focus on the game itself, not the dev process. |
| **r/godot** | 300K+ | Technical deep-dive. "How I built a complex strategy game in Godot with 190K lines of GDScript." |
| **r/MachineLearning** | 2.5M+ | The AI angle. "Using LLMs for game development: 960 commits in 3 weeks." Data-driven post. |
| **r/programming** | 5M+ | Technical angle. The commit velocity data, the testing strategy, the audit workflow. |
| **r/artificialintelligence** | 1M+ | The productivity angle. "From 1 commit/day to 110 commits/day with AI coding tools." |
| **r/ClaudeAI** | Growing | The Claude Code workflow. Show the human-AI interaction loop. |

**Reddit rules of engagement:**
- **DO:** Present your game and ask for genuine feedback. Include screenshots and link a YouTube gameplay video.
- **DO:** Share the data (commit chart, before/after). Data performs well on Reddit.
- **DO:** Engage in every comment thread for 24-48 hours after posting.
- **DON'T:** Spam the same post to 10 subreddits simultaneously.
- **DON'T:** Be overtly promotional. Frame as sharing your journey, not advertising.
- **DON'T:** Post to r/gaming or r/Steam — they ban self-promotion.
- **TIMING:** Post on Tuesday-Thursday, 8-10 AM EST for maximum visibility.
- **BUILD KARMA FIRST:** Comment genuinely in these communities for 1-2 weeks before posting your own content.

### 5.3 Twitter/X Strategy

X is essential for connecting with **dev community, journalists, and influencers** — but weaker for reaching players directly.

**Content strategy:**
- **The thread:** Write a Twitter thread version of your story. Lead with the commit chart image. Thread format: 8-12 tweets, each with a visual or data point.
- **Daily dev content:** Short clips, screenshots, stats from the dev process
- **Engage with AI coding discourse:** Reply to vibe coding discussions with your real data
- **Tag relevant accounts:** @AnthropicAI, @GodotEngine, game dev communities
- **Hashtags:** #indiedev #gamedev #AIcoding #godotengine #devlog

**X-specific notes:**
- The algorithm deprioritizes tweets with external links — post the content natively, add links in replies
- Quote-tweet AI coding discussions with your own data/experience
- Video clips autoplay and get higher engagement than static images
- Post 2-5 times per day during launch week

### 5.4 TikTok / Instagram Reels Strategy

**Declining organic reach in 2026** — but still valuable for discovery if content is strong.

**Repurpose YouTube Shorts directly.** Same 9:16 vertical format. Post to all three (YouTube Shorts, TikTok, Instagram Reels) simultaneously.

**TikTok-specific:**
- Hook in first 1-3 seconds or viewers swipe
- Hashtags: #indiegamedev #gamedev #AIcoding #vibecoders #coding #programming
- Post 3-5x per week minimum
- The commit graph animation is perfect TikTok content — visual, surprising, shareable
- Budget $500-$2,000 for Spark Ads on best-performing organic content if desired

### 5.5 Hacker News Strategy

HN is **high-risk, high-reward**. A front page hit drives tens of thousands of highly engaged tech readers.

**How to approach:**
- **Post type:** "Show HN: [Game Name] – A tabletop strategy game built by one developer with AI coding tools"
- **Timing:** Tuesday-Thursday, 8-10 AM Pacific Time
- **Title:** Clear, descriptive, no clickbait. "Show HN: I used Claude Code to build a 190K-line strategy game in Godot"
- **Link to:** A blog post or the game itself — NOT a YouTube video (HN prefers articles)
- **Engage in comments** for 48 hours. Be humble, transparent, technical. Show the data.
- **What HN loves about your story:** The commit velocity data, the honest "what worked/what didn't", the technical depth, the open discussion of AI limitations
- **What to avoid:** Promotional language, asking for upvotes, over-hyping

**Write a companion blog post** (hosted on your own site or a platform like dev.to) that tells the technical story with data, charts, and honest reflection. This is your HN submission.

**Be prepared to iterate:** Posts sometimes need 5-10 attempts with different titles/timing before hitting.

### 5.6 Discord Strategy

**Phase 1 (Launch):** Join existing communities, don't create your own yet.

| Community | Purpose |
|-----------|---------|
| Godot Discord | Share technical devlog posts, help others, build credibility |
| Warhammer community Discords | Engage as a fan, mention the game naturally when relevant |
| AI/Claude Code communities | Share your workflow, data, lessons learned |
| Indie game dev Discords | Cross-promote, find collaborators, share devlogs |

**Phase 2 (After 500+ YouTube subs):** Create your own Discord for playtesters, community feedback, and direct engagement with fans. Include channels for: #devlog, #gameplay, #bug-reports, #suggestions, #general.

### 5.7 itch.io Strategy

- Publish the game (free or pay-what-you-want) on itch.io
- The devlog feature on itch.io drives discovery
- Cross-link between itch.io page and YouTube channel
- itch.io has a built-in community of indie game enthusiasts who actively browse for new titles

### 5.8 Blog Post / Written Content

Write a detailed technical blog post version of the story for:
- **Hacker News** submission (required — HN prefers articles over videos)
- **Dev.to** community
- **Medium** (for broader reach)
- **Your own website** (for SEO long-term)

The blog post should include:
- The commit timeline chart (static and animated versions)
- Before/after screenshots
- The data table from [`DEV_BLOG_CONTENT_OUTLINE.md`](DEV_BLOG_CONTENT_OUTLINE.md)
- Honest reflection on what worked and what didn't
- Technical details about the Claude Code workflow
- Links to the YouTube video and game

### 5.9 Cross-Platform Content Repurposing

**One video → 15+ pieces of content:**

| Source | Derivative | Platform |
|--------|-----------|----------|
| Hero video | 5-8 YouTube Shorts | YouTube |
| Hero video | Same Shorts | TikTok, Instagram Reels |
| Hero video | Twitter thread (8-12 tweets) | X |
| Hero video | Blog post (2,000-3,000 words) | Dev.to, Medium, personal site |
| Hero video | HN submission | Hacker News |
| Hero video | Reddit posts (3-4 different angles for different subs) | Reddit |
| Commit chart | Static image posts | All platforms |
| Before/after gameplay | GIF/clip | Reddit, X, Discord |
| Key stats | Infographic | X, LinkedIn, Reddit |
| Lessons learned | Thread/carousel | X, LinkedIn |

### 5.10 The Three-Pillar Content Strategy

Your project sits at the intersection of three highly active communities. Structure ALL content around these pillars:

| Pillar | Content Focus | Primary Platforms | Target Audiences |
|--------|---------------|-------------------|------------------|
| **The Game** | Gameplay, faction showcases, rules implementation, visual design | r/Warhammer40k, r/IndieGaming, TikTok, YouTube | Warhammer fans, strategy gamers, indie game enthusiasts |
| **The Tech** | Godot engine development, GDScript solutions, game architecture deep-dives | r/godot, Godot Discord, r/gamedev, YouTube | Game developers, Godot users, programmers |
| **The Process** | AI coding workflow, Claude Code capabilities/limitations, honest process documentation | Twitter/X (#VibeCoding), Hacker News, LinkedIn, r/programming | AI/tech enthusiasts, developers, entrepreneurs |

Each pillar feeds a different audience, but they all drive traffic back to the same YouTube channel. This gives you **3x the content surface area** of a typical indie dev.

**Why this matters:** A single devlog video can generate:
- A "Game" clip for r/Warhammer40k (focus on the gameplay)
- A "Tech" clip for r/godot (focus on the Godot implementation)
- A "Process" clip for Twitter (focus on the AI coding workflow)
- Same video, three angles, three audiences

### 5.11 LinkedIn Strategy (The Overlooked Platform)

LinkedIn is surprisingly valuable for the "Process" pillar:
- Only **1% of users** post weekly — enormous opportunity with low competition
- Engagement rates up **30% year-over-year** (avg 5.0% engagement by impressions)
- Video posts average **5.6% engagement** vs 4.0% for text-only
- The professional audience is deeply interested in "how AI changes software development"

**Post 2-3x/week:**
- "What I learned building a strategy game with Claude Code" (thought leadership)
- Short video clips (<90 sec) showing AI coding workflow
- Carousel posts showing before/after code with AI
- Reflections on productivity, tooling, workflow

**LinkedIn is NOT for:** Warhammer fan content or gameplay showcases. Save those for Reddit/X/TikTok.

### 5.12 Community-Specific Intel

**Warhammer 40K community:**
- r/Warhammer40k (1.4M members), r/WarhammerCompetitive, faction-specific subs
- Hammerit Discord (22K+), faction servers
- Specialist forums: DakkaDakka, Goonhammer, Woehammer (deepest tactical analysis)
- YouTube: battle report channels (Tabletop Titans, Play On Tabletop), lore (Luetin09, Baldermort)
- **This community will scrutinize your rules implementation closely** — emphasize accuracy
- Warhammer Darktide brought millions of video gamers into 40K (18% increase in starter set sales)

**Godot community:**
- r/godot (very active), Official Godot Discord (~65K), Godot Cafe Discord (~86K)
- Official forum, GitHub, Rocket.Chat for engine contributors
- Posts tagged **#MadeWithGodot** perform especially well
- The community is passionate about open-source and loves ambitious projects

**AI coding / vibe coding community:**
- Twitter/X: **#VibeCoding has 150,000+ posts per month** — the most active real-time platform
- Hacker News: regular "Show HN" threads about AI coding projects
- Conferences: VibeX 2026 (first international vibe coding workshop), AI Coding Summit
- Tool communities: Cursor, Claude Code ecosystems
- Growing newsletter/Substack ecosystem around AI engineering

---

## Phase 6: Launch Sequence

### The 2-Week Launch Plan

**Week -1 (Pre-launch — Shorts + Social Seeding):**

| Day | Action |
|-----|--------|
| Mon | Post Short #1 (commit graph animation) to YouTube, TikTok, Reels |
| Tue | Post Short #2 (before/after split) + first X thread teaser |
| Wed | Post Short #3 (160-commit day) + Reddit teaser on r/gamedev |
| Thu | Post Short #4 (AI vs AI match) + engage in AI coding discussions on X |
| Fri | Post Short #5 (debugging struggle) |
| Sat | Post Short #6 (stats reveal) |
| Sun | Post Short #7 (terminal timelapse) + "big video dropping this week" teaser |

**Week 0 (Launch Week):**

| Day | Action |
|-----|--------|
| **Wed 3PM** | **PUBLISH HERO VIDEO** (Wed-Thu is optimal for tech/gaming crossover) |
| Wed 3:30PM | Post announcement on X with native video clip + link in reply |
| Wed 4PM | Post to r/gamedev with commit chart + video link |
| Wed 4:30PM | Post to r/indiegaming with gameplay clip + video link |
| Wed 5PM | Share in Godot Discord, game dev Discords |
| Thu 8AM PT | Submit blog post to Hacker News ("Show HN: ...") |
| Thu 9AM | Post to r/godot with technical angle |
| Thu 10AM | Post to r/programming or r/artificialintelligence |
| Thu-Fri | Engage in ALL comment threads across all platforms (48 hours minimum) |
| Fri | Post Short #8 + respond to all YouTube comments |
| Sat | Cross-post any traction ("Thanks to everyone who..." engagement posts) |
| Sun | Publish blog post on Dev.to and Medium |

### 5 Key Rules for Launch Week

1. **Respond to every comment** in the first 48 hours. Engagement signals matter enormously for the algorithm AND for community building.
2. **Don't post the same link everywhere simultaneously.** Stagger by 30-60 minutes. Tailor framing for each platform.
3. **Monitor YouTube Studio analytics in real-time.** If CTR is below 5%, consider swapping thumbnail. If retention drops below 40% at a specific point, note it for future videos.
4. **Pin a comment** on the YouTube video that asks a question to drive engagement (e.g., "What feature should I build next?")
5. **The first 48 hours of a YouTube video's life determine its long-term performance.** The algorithm evaluates early signals to decide whether to push the video to broader audiences.

---

## Phase 7: Ongoing Content Calendar

### Weekly Cadence (Post-Launch)

| Day | Content | Platform |
|-----|---------|----------|
| Mon | Short (clip from upcoming episode) | YouTube, TikTok, Reels |
| Tue | Dev update post (screenshot + caption) | X, Reddit |
| **Wed** | **Episode release** (from the 6-episode series) | **YouTube** |
| Thu | Short (highlight from episode) | YouTube, TikTok, Reels |
| Fri | Community engagement (reply to comments, Reddit threads) | All |
| Sat | Short (bonus clip or outtake) | YouTube, TikTok, Reels |

### Episode Release Schedule

Release weekly on Wednesdays, starting 1 week after hero video:

| Week | Episode | Length | Title Angle |
|------|---------|--------|-------------|
| 1 | Hero Video | 15-18 min | "I Built a Strategy Game Solo. Then AI Changed Everything." |
| 2 | Ep 1: The Foundation | ~10 min | "Building a Wargame from Scratch in Godot" |
| 3 | Ep 2: The Rules Engine | ~12 min | "Why Tabletop Rules Are Harder Than You Think to Code" |
| 4 | Ep 3: The Long Winter | ~5 min | "Why I Almost Quit (And What Brought Me Back)" |
| 5 | Ep 4: Enter the AI | ~15 min | "The Day AI Audited My Entire Codebase" |
| 6 | Ep 5: The Supernova | ~15 min | "552 Commits in 5 Days — Inside the AI Explosion" |
| 7 | Ep 6: Shipping It | ~10 min | "What 190,000 Lines of AI-Assisted Code Actually Looks Like" |

### Playlist Strategy

Create playlists — they improve algorithm performance by encouraging binge-watching:
- **"The Full Story"** — Hero video + all 6 episodes in order
- **"AI Coding in Practice"** — Episodes 4, 5, 6 + any future AI workflow content
- **"Building a Strategy Game in Godot"** — Episodes 1, 2 + any future Godot tutorials
- **"Shorts"** — All shorts in a playlist

### Long-Term Content Ideas (After Series)

| Content Type | Frequency | Example |
|---|---|---|
| AI workflow tutorials | Biweekly | "How I Use Claude Code for Game Dev: My Exact Workflow" |
| Game design deep-dives | Monthly | "Designing AI That Plays Like a Human: Scoring Functions vs Neural Nets" |
| Update videos | As needed | "New Faction, New Mechanics: March Update" |
| Community challenges | Monthly | "Can You Beat My AI on Hard Mode?" |
| Collaborations | Quarterly | Guest appearances with other gamedev/AI creators |

---

## Metrics to Track

### YouTube

| Metric | Target (First Month) | Target (Month 3) |
|--------|---------------------|-------------------|
| Hero video views | 5,000+ | 25,000+ |
| Average view duration | 50%+ retention | 55%+ retention |
| CTR | 5%+ | 7%+ |
| Subscribers | 200+ | 1,000+ |
| Shorts avg views | 1,000+ | 5,000+ |

### Cross-Platform

| Platform | Metric | Target |
|----------|--------|--------|
| Reddit | Total upvotes across posts | 500+ |
| X | Followers gained in month 1 | 200+ |
| Hacker News | Front page hit | 1 within first 3 attempts |
| itch.io | Game page views | 1,000+ |
| Discord | Members (after creation) | 50+ |

---

## Budget Summary

### Free Path (Recommended to Start)

| Item | Cost |
|------|------|
| OBS Studio | $0 |
| DaVinci Resolve Free | $0 |
| Canva Free | $0 |
| Audacity | $0 |
| YouTube Audio Library | $0 |
| Flourish Free | $0 |
| itch.io hosting | $0 |
| **Total** | **$0** (+ mic if needed) |

### Recommended Investments (After First Video)

| Item | Cost | ROI |
|------|------|-----|
| USB Microphone | $70-100 | High — audio quality is the #1 production value differentiator |
| Epidemic Sound | $9.99/mo | Medium — better music, no copyright risk |
| TubeBuddy/VidIQ Pro | $7.50/mo | Medium — SEO optimization, A/B testing, competitor analysis |
| TikTok Spark Ads | $500 one-time | Variable — only boost top-performing organic content |
| **Total Year 1** | ~$400-700 | |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| **GW IP takedown** | Rebrand BEFORE publishing anything (Phase 1.1) |
| **Low initial views** | Normal for new channels. Shorts strategy provides discovery engine. Focus on retention metrics, not view counts. |
| **Negative AI sentiment** | Frame honestly — "AI helped me do what I couldn't alone" not "AI replaced my work." Show failures alongside successes. |
| **Burnout from content treadmill** | Batch-produce: record 3-4 episodes in one session, edit over 2 weeks. Shorts can be cut from existing footage. |
| **Algorithm changes** | Diversify across platforms. Build email list / Discord for direct audience access. |
| **TikTok ban/restrictions** | Don't over-invest. YouTube Shorts + Instagram Reels cover the same format. |

---

## The Single Most Important Thing

**The commit timeline chart is the center of gravity for this entire campaign.**

It is simultaneously:
- Your YouTube thumbnail element
- Your Twitter/X thread lead image
- Your Reddit post hero image
- Your Hacker News blog post header
- Your TikTok/Shorts hook
- Your hero video opening shot

**Make it beautiful. Make it animated. Make it the first thing anyone sees.**

The flat line going vertical tells the entire story without a single word. That image, more than anything else, is what will make people click.

---

---

## Common Mistakes That Kill Channels (Avoid These)

1. **Misleading packaging** — In the Gemini era, clickbait kills channels. If your title/thumbnail promises something your video doesn't deliver, satisfaction tanks and distribution stops.
2. **Long intros / slow starts** — 55% of viewers leave in the first 60 seconds. Start with the value immediately.
3. **No niche / mixed content** — If uploads cover AI, vlogs, and cooking, the algorithm has no idea who to show your videos to. Stay in your three pillars.
4. **Designing thumbnails for desktop** — 70% of views are mobile. If text is unreadable on a phone, you lose 30-50% of clicks.
5. **Ignoring Shorts entirely** — Creators who integrate Shorts see **27% faster audience growth**.
6. **Ghost-town comment sections** — Not replying signals a dead channel. Reply to everything early on.
7. **Optimizing for watch time over satisfaction** — A short video with 83% retention sends a stronger signal than a long video with 40% retention. Don't pad with filler.
8. **Over-reliance on AI-generated content** — YouTube flags "synthetic or deceptive media." Your unique perspective must be front and center.
9. **Giving up too early** — Growth is slow then exponential. Most creators quit before the inflection point at 3-6 months. The algorithm needs time to learn your audience.
10. **Posting to r/gaming or r/Steam** — They ban self-promotion. Use r/IndieDev, r/IndieGaming, r/gamedev instead.

---

## Growth Timeline Expectations

Be realistic about growth trajectory:
- **Month 1-3:** Slow growth. Focus on retention metrics, not view counts. Build karma on Reddit, followers on X.
- **Month 3-6:** Algorithm starts to recognize your audience. Noticeable traction if consistency held.
- **Month 6-12:** Meaningful growth. Potential exponential inflection point.
- **Early monetization (before ads):** Affiliate links, Patreon, digital products.
- **YouTube Basic Monetization:** 500 subscribers + 3 public videos + 3,000 watch hours (or 3M Shorts views) in 12 months.

**Key stat:** 78% of successful creators use documented content strategies; those with strategies grow **3.2x faster** (Influencer Marketing Hub 2026).

---

## Sources

### YouTube Algorithm
- [YouTube Algorithm Updates 2026 — OutlierKit](https://outlierkit.com/resources/youtube-algorithm-updates/)
- [YouTube Algorithm 2026: How It Works — VidIQ](https://vidiq.com/blog/post/understanding-youtube-algorithm/)
- [How to Get Discovered on YouTube 2026 — TubeBuddy](https://www.tubebuddy.com/blog/how-to-get-discovered-on-youtube-why-new-creators-are-being-pushed-in-2025/)
- [The YouTube Algorithm — Sprout Social](https://sproutsocial.com/insights/youtube-algorithm/)
- [Small Creators Winning in 2026 — Medium](https://medium.com/write-a-catalyst/the-youtube-algorithm-has-changed-forever-heres-how-creators-win-in-2026-1d453d3a4e8f)
- [YouTube's Gemini Update Guide](https://masculinesynergy.com/youtube-algorithm-2026-gemini-update-guide/)
- [How Gemini AI Changes Everything — Medium](https://medium.com/@alieat272/youtubes-secret-algorithm-update-how-gemini-ai-is-changing-everything-for-creators-in-2026-728ba65b3008)

### SEO & Optimization
- [YouTube SEO Best Practices 2026 — Learning Revolution](https://www.learningrevolution.net/youtube-seo/)
- [YouTube SEO — Backlinko](https://backlinko.com/how-to-rank-youtube-videos)
- [YouTube SEO — SEO Sherpa](https://seosherpa.com/youtube-seo/)
- [Video SEO Best Practices 2026 — VdoCipher](https://www.vdocipher.com/blog/video-seo-best-practices/)

### Shorts Strategy
- [YouTube Shorts RPM & Growth 2026 — AIR Media-Tech](https://air.io/en/creators-spotlight/still-doubting-shorts-in-2026-were-not-heres-why)
- [YouTube Shorts Best Practices 2026 — JoinBrands](https://joinbrands.com/blog/youtube-shorts-best-practices/)
- [YouTube Shorts Best Practices 2026 — Miraflow](https://miraflow.ai/blog/youtube-shorts-best-practices-2026-complete-guide)

### Posting Times
- [Best Time to Post on YouTube 2026 — RecurPost](https://recurpost.com/blog/best-time-to-post-on-youtube/)
- [Best Times to Post — Social Pilot](https://www.socialpilot.co/blog/best-time-to-post-on-youtube)

### Social Media Strategy
- [How To Market Your Indie Game In 2025 — NipsApp](https://nipsapp.com/how-to-market-your-indie-game-in-2025-from-steam-to-social-media/)
- [2026 Indie Game Marketing Guide — Game Developers](https://www.game-developers.org/2026-indie-game-production-marketing-guide)
- [Game Marketing On Social Media 2025 — 5W PR](https://www.5wpr.com/new/game-marketing-on-social-media-in-2025-building-interactive-campaigns-for-indie-success/)
- [Promote Your Indie Game On Reddit — IMPRESS Games](https://impress.games/blog/how-to-promote-your-indie-game-on-reddit)
- [TikTok's Changing Landscape for Game Marketing 2026 — Cloutboost](https://www.cloutboost.com/blog/tiktoks-changing-landscape-for-game-marketing-in-2026-what-developers-need-to-know)

### Hacker News
- [How to Hack Hacker News — Indie Hackers](https://www.indiehackers.com/post/how-to-hack-hacker-news-and-consistently-hit-the-front-page-56b4a04e12)
- [I Vibe Coded a Game to the Front Page of HN — Kate Catlin](https://katecatlin.substack.com/p/i-vibe-coded-a-game-to-the-front)
- [How to Launch on HN: 500+ Upvotes — Calmops](https://calmops.com/indie-hackers/hacker-news-launch-500-upvotes/)

### Community & Platforms
- [Warhammer 40K Online Community — Adeptus Ars](https://www.adeptusars.com/guides/best-w40k-forums)
- [Godot Engine Community](https://godotengine.org/community/)
- [Discord Servers for Game Devs — Xsolla](https://accelerator.xsolla.com/blog/discord-servers-that-game-devs-should-join)
- [r/Warhammer40k Stats](https://gummysearch.com/r/Warhammer40k/)

### General Research
- See [`VIDEO_PRODUCTION_RESEARCH.md`](VIDEO_PRODUCTION_RESEARCH.md) for 50+ additional sources on tools, aesthetics, AI coding landscape, and competitive positioning

---

*This plan synthesizes research from 80+ sources across YouTube algorithm analysis, social media strategy, indie game marketing, and community building. Updated March 2026.*
