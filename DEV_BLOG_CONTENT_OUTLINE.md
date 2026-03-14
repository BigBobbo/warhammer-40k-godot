# Dev Blog Content Outline
## "6 Months Solo. Then AI Happened. 1,067 Commits Later, I Have a Full Strategy Game."

*Content plan for hero video + episodic breakdown*

---

## THE HOOK (Hero Video — 18-25 min)

**Title options:**
- "I Built a Strategy Game for 6 Months — Then AI Took It to Another Level"
- "1,067 Commits: How One Dev + AI Built a Complete Tabletop Strategy Game"
- "I Spent 6 Months on a Game. AI Did More in 2 Weeks Than I Did in 5 Months."
- "From Side Project to 190,000 Lines of Code — The AI Acceleration Story"

**Opening shot:** Two-part reveal. First: a quiet commit graph — one commit per day, steady for months. Then: the graph *explodes*. 160 commits in a single day. The line goes vertical. Text overlay: "What happened?"

**The Pitch (first 60 seconds):**
> Last August I started building a digital version of a tabletop wargame in Godot. One commit a day. Movement. Shooting. Charge phase. I was chipping away at it for months — 100 commits over 5 months. Then in February, I plugged in AI coding tools. In the next 3 weeks, I made 960 more commits. 190,000 lines of code. 2,500 automated tests. A full game with an AI opponent that actually plays tactically. This is the story of what happens when a solo dev gets AI superpowers.

**Key stats to flash on screen:**
- 1,067 total commits over 6 months
- 100 commits in the first 5 months (manual coding)
- 960+ commits in the final 3 weeks (AI-assisted)
- 190,000+ lines of GDScript
- 2,500+ automated tests across 153 test files
- 124 merged AI-authored pull requests
- 5 complete game phases
- 30+ stratagems
- 15+ secondary missions
- Full online multiplayer support
- 3 authors: OisinRob (760), Claude (191), BigBobbo (116)

---

## THE REAL NARRATIVE ARC — 6 Months in 3 Acts

### Act 1: "The Solo Grind" (Aug 19 – Oct 29, 2025) — 103 commits over 10 weeks

**The origin story.** This is the relatable part. A solo dev, working on a passion project, one commit at a time.

**August 19, 2025 — Day 1 (2 commits):**
- `080a256` Initial commit: Warhammer 40k Godot game with movement phase fixes
- `82da764` Implement visual range indicators and fix target selection in shooting phase
- *"On Day 1 I had a board, some tokens, and a movement phase that mostly worked."*

**The first month (Aug 19 – Sep 19, 38 commits):**
One commit per day. Methodical, steady progress. Building the fundamentals by hand:
- Shooting phase with range indicators
- Charge phase with working movement
- Fight phase UI and engagement detection
- Save/load system with multiple slots
- Multi-step movement
- Enemy Ork army implementation
- Mathhammer probability calculator
- Terrain system (Chapter Approved Layout 2)
- Line of sight with base-to-base visibility
- Mission scoring (Take and Hold)
- Measuring tape tool
- Model overlap prevention
- Deployment formations
- Wall collision detection

**The pace:** 38 commits in 32 days. Roughly one feature per day. Real, foundational work — but slow.

**The multiplayer push (Sep 29 – Oct 29, 65 commits):**
Things speed up slightly. Multiplayer brings complexity:
- Transport system (embark/disembark)
- Multiplayer deployment sync
- Standardized UI panels across all phases
- Non-circular base rendering (oval vehicles, rectangular models)
- Shooting phase enhanced with modifiers
- Death markers for destroyed models
- Weapon cycling and auto-choose
- GUT testing framework
- Fight phase pile-in and consolidate
- Objective range edge-to-edge calculations
- Integration testing framework

**Narrative beat:** "By the end of October, I had a working game. Two players could deploy, move, shoot, charge, fight, and score. But it was held together with duct tape. The multiplayer sync was fragile. The UI was inconsistent. The AI didn't exist yet. I'd been at this for 10 weeks and I had... a prototype."

**Then silence.** One commit on November 27th. Then nothing until February 1st.

**B-roll:** Early gameplay recordings showing the jank. The one-commit-per-day rhythm. GitHub issue tracker growing. The commit graph flatline in December and January.

---

### Act 2: "The Return — and the Discovery" (Feb 1 – Feb 15, 2026) — 180 commits in 2 weeks

**The comeback.** Three months of nothing. Then on February 1st, 15 commits in a single day. What changed?

**Feb 1 — The infrastructure day (15 commits):**
All OisinRob, all manual. But a clear new ambition:
- WebSocket multiplayer support for online play
- Server Dockerfile for Fly.io deployment
- Web export workflow for itch.io
- Node.js WebSocket relay server
- *"I came back with a mission. I wanted this online. I wanted people to actually play it."*

**Feb 4-9 — Warming up (21 commits):**
- Online lobby system
- Web deployment fixes
- Cloud army storage
- Network reconnection

**Feb 10 — The shift begins (11 commits):**
- Feel No Pain defensive ability
- Shape-aware edge-to-edge distances for all measurements
- Tests for 10e hit roll rules
- *"This was the day I started using Claude Code seriously. And immediately the pace changed."*

**Feb 11 — The first AI day (38 commits):**
This is where the graph starts bending upward. The commit log tells the story:
- CHARACTER leader attachment system
- Movement phase audit vs 10e rules
- Deployment phase audit
- Charge phase audit
- Command phase audit
- Fight phase audit
- CP generation and display
- Battle-shock mechanics
- Deployment progress indicator
- Toast notification system
- *"In one day, Claude audited every phase of my game against the actual rulebook and filed the gaps. Then it started filling them."*

**First Claude-authored commit:** `2c9ea0d` (Oct 23, 2025) — GUT testing enhancements. But Claude really arrived in force on Feb 11.

**Feb 12-15 — The acceleration (92 commits):**
- Stratagems: Insane Bravery, Go to Ground, Smokescreen
- StratagemManager system
- AI movement toward objectives
- Terrain/deployment editor (web-based)
- Cloud army upload pipeline
- AI deployment fixes
- Online play bug fixes

**Narrative beat:** "In two weeks, I'd made more commits than in the entire first 5 months. And it wasn't just volume — each commit was landing real features. Audits. Stratagems. Systems. Things that would have taken me weeks each were landing in hours."

**Visual:** Split screen: left side shows the Oct 2025 commit log (one per day), right side shows Feb 11 (38 in one day). Same developer. Same project. Different tools.

---

### Act 3: "The Supernova" (Feb 16 – Mar 1, 2026) — 784 commits in 14 days

**This is where the story goes exponential.** The final two weeks produced more output than the entire previous 5 months combined.

#### Week 1: "160 Commits in a Day" (Feb 16-20, 552 commits)

**Feb 16 (35 commits):**
- Terrain rendering on multiplayer client
- Unit disembark fixes
- Web-based terrain/deployment editor
- AI movement with terrain avoidance
- Advance movement system
- Overwatch stratagem

**Feb 17 (63 commits):**
- AI targeting improvements
- Command Re-roll stratagem
- Weapon keywords: Lethal Hits, Devastating Wounds, Sustained Hits
- Unit abilities: Martial Ka-tah, Waaagh!
- Secondary missions framework

**Feb 18 (151 commits):**
- Rapid Ingress deep strike stratagem
- Fight selection dialog sync
- Desperate Escape mechanic
- One Shot weapons
- AI shooting range consideration
- AI turn summary panel
- Damaged profiles system
- Deadly Demise (exploding vehicles)
- Board rotation for Player 2
- Overwatch dialog fixes
- *"151 commits in one day. That's more than my entire first two months combined."*

**Feb 19 (154 commits):**
- Swift Onslaught, Sentinel Storm, Throat Slittas abilities
- Duplicate function definition fixes
- Game stuck at ROLL_OFF phase fix
- Multiplayer formation fixes
- Model drag position persistence
- Waaagh! system complete

**Feb 20 (160 commits — the peak day):**
- Secondary missions panel
- Multiple unit ability implementations
- AI movement path visualization
- Shooting target line visualization
- Multi-target charge declarations
- AI speed controls
- Difficult terrain penalties
- *"160 commits. The most productive single day of development. More than my entire August and September combined."*

**Narrative beat:** "I stopped counting features. The commit log was scrolling faster than I could review. Three AI-authored PRs landing per hour. The game was growing like a living thing."

#### Week 2: "Polish and Ship" (Feb 21-28, 223 commits)

**Feb 21 (41 commits):**
- Fullscreen game
- Terrain movement fixes
- Objective detection for non-circular bases
- Player scores in top bar
- Primary mission selection in multiplayer

**Feb 22 (39 commits):**
- AI deep strike stall fixes
- AI thinking logs
- AI vs AI fight phase fixes
- Skip UI dialogs for AI turns

**Feb 23 (49 commits):**
- AI decision-making overhaul
- Advance movement bug fixes
- Enhanced game logging with dice rolls
- Stratagem feedback systems

**Feb 24-25 (32 commits):**
- Integration day — merging accumulated PRs
- AI deployment for non-standard zones
- UX overhaul pass

**Feb 26-28 (62 commits):**
- Edge-to-edge coherency (rules accuracy)
- Unit Image Editor tool
- Character deployment fixes
- Reserves point cap correction (25% → 50%)
- Reserves destruction at Round 3
- Coherency distance display during placement
- Dialog size standardization
- Animated sprite system
- Comprehensive AI documentation
- Stratagem advance reroll with feedback
- Deployment zone toggle (Z key)
- Enhanced game logging

**The AI difficulty ladder that emerged:**
1. Easy — random valid moves
2. Normal — full scoring with noise
3. Hard — stratagems + multi-phase planning
4. Competitive — zero noise, trade analysis, look-ahead

**Narrative beat:** "On Feb 22, I watched two AI armies play a complete 5-round game against each other. The competitive AI was focus-firing wounded units, positioning for Rapid Fire range bonuses, using stratagems at the right moment, and pivoting to objective play in the late rounds. It had 82 distinct behaviors and I hadn't written a single one of them."

---

## THE NUMBERS THAT TELL THE STORY

| Period | Duration | Commits | Commits/Day | Phase |
|--------|----------|---------|-------------|-------|
| Aug 19 – Sep 19 | 32 days | 38 | 1.2 | Solo foundation |
| Sep 29 – Oct 29 | 31 days | 65 | 2.1 | Multiplayer push |
| Oct 30 – Jan 31 | 93 days | 2 | 0.02 | Hibernation |
| Feb 1 – Feb 9 | 9 days | 36 | 4.0 | Return & ramp-up |
| Feb 10 – Feb 15 | 6 days | 144 | 24.0 | AI enters the picture |
| Feb 16 – Feb 20 | 5 days | 552 | 110.4 | Hyperdrive |
| Feb 21 – Mar 1 | 9 days | 232 | 25.8 | Polish & ship |

**The multiplier:** From 1.2 commits/day (solo) to 110 commits/day (AI-assisted) = **~90x acceleration** at peak.

**Author breakdown:**
- OisinRob: 760 commits (71%) — the human driving the project
- Claude: 191 commits (18%) — AI-authored code
- BigBobbo: 116 commits (11%) — merge commits and direct pushes

---

## THE REFLECTION (Final 5-6 minutes)

### The Real Story Is Not "AI Built a Game"

The real story is: **a human built a game for 5 months, hit a wall, and AI helped them break through it.**

Without those first 100 manual commits, the AI would have had nothing to work with. The architecture was set. The phase structure was defined. The multiplayer framework existed. The game *worked* — it just needed 10x more features to be complete.

### What Worked
- **The human foundation:** 100 commits of manual work created the scaffolding that AI could build on. Without understanding the game deeply, the AI prompts wouldn't have worked.
- **The audit-driven workflow:** Having Claude audit each phase against the actual rulebook was transformative. It found gaps the human had missed or deferred.
- **PR-based workflow:** 124 Claude-authored PRs, each reviewed before merge. Not "AI writes everything" — "AI proposes, human approves."
- **Testing culture:** Starting with a testing framework in October meant the AI could make aggressive changes with confidence. 2,500+ tests by the end.
- **Treating AI as a junior dev:** Clear specs, code review, bug filing when it got things wrong.

### What Didn't Work
- **The monolith problem:** AIDecisionMaker.gd ballooned because AI favors adding to existing files over refactoring into modules.
- **Cascading rule interactions:** Implementing one rule would subtly break another. The AI didn't always catch regressions across files.
- **Multiplayer sync was fragile:** Many bug fixes in the final weeks were multiplayer sync issues the AI introduced because it didn't fully understand the networking model.
- **Volume ≠ quality:** 160 commits in a day meant some things shipped that shouldn't have. The review bottleneck was real.

### What It Means
- **Not "AI replacing developers"** — it's about amplifying ambition. One person + AI = what used to take a team.
- **The bottleneck shifted** from "writing code" to "knowing what to build." Game design knowledge and rules expertise mattered more than coding ability.
- **Code review is the new coding.** 80% of the work in February was reviewing AI output, testing it, and filing the next task.
- **The foundation matters.** Those 100 manual commits weren't wasted work — they were the training data for every prompt that followed.

---

## EPISODIC BREAKDOWN (6 episodes)

### Episode 1: "The Foundation" (Aug – Sep 2025)
*~10 min*
- Why this project? The ambition of digitizing a complex tabletop wargame
- Setting up Godot and explaining the rules
- The 1-commit-per-day grind: movement, shooting, charge, fight
- Terrain, line of sight, deployment formations
- End card: working prototype after 38 commits

### Episode 2: "The Rules Engine" (Sep – Oct 2025)
*~12 min*
- Deep dive into 10th edition combat resolution
- Weapon keywords: Blast, Rapid Fire, Melta, Lethal Hits, Devastating Wounds
- The wound allocation priority system
- Cover and line of sight
- Multiplayer sync challenges
- Bug montage: all the ways rules can break each other
- The testing framework arrives

### Episode 3: "The Long Winter" (Nov 2025 – Jan 2026)
*~5 min — short but important for the narrative*
- Why projects stall
- One commit in 3 months
- What changed: the decision to go online
- The Feb 1 comeback: WebSocket multiplayer, Fly.io, itch.io web export
- 15 infrastructure commits in a single day

### Episode 4: "Enter the AI" (Feb 10-15, 2026)
*~15 min — the turning point, this is the draw*
- What is Claude Code and how does the workflow operate?
- The first audit: Claude reads the entire codebase and compares it to the rulebook
- 38 commits on Feb 11 — the first AI-powered day
- Stratagems, battle-shock, CP generation — features that would have taken weeks
- The PR workflow: how a human stays in control of AI output
- Demo: before-AI vs after-AI gameplay side by side

### Episode 5: "The Supernova" (Feb 16-20, 2026)
*~15 min*
- 552 commits in 5 days
- The 160-commit day
- AI architecture: scoring functions, not neural networks
- Target priority, movement AI, stratagem usage
- Unit abilities landing faster than they can be tested
- The review bottleneck: when AI output exceeds human bandwidth
- Demo: Easy vs Competitive AI playing the same scenario

### Episode 6: "Shipping It" (Feb 21 – Mar 1, 2026)
*~10 min*
- Final rules audit against source material
- The polish pass: edge-to-edge distances, animated sprites, dialog consistency
- AI vs AI showcase match
- The numbers: 1,067 commits, 190k lines, 2,500 tests
- Lessons learned: what this means for solo devs
- What's next

---

## VISUAL ASSETS NEEDED

### Recordings to capture:
- [ ] Clean full-game playthrough (Deployment through Scoring, ~5 rounds)
- [ ] AI vs AI match at Competitive difficulty
- [ ] Side-by-side: Easy AI vs Competitive AI on same scenario
- [ ] AI thinking overlay close-ups (decision explanations)
- [ ] Dice roll animations in action
- [ ] Charge arrows and movement path visualization
- [ ] Terrain and line-of-sight blocking
- [ ] Mathhammer Monte Carlo simulation
- [ ] The commit graph / PR list on GitHub (show the exponential curve)
- [ ] Code scrolling through AIDecisionMaker.gd (show the scale)
- [ ] Early gameplay footage from Aug/Sep (the janky prototype)
- [ ] Feb gameplay footage (the polished version) — for before/after comparison

### Screen recordings of the dev process:
- [ ] Claude Code terminal sessions (the human-AI interaction)
- [ ] PR creation and merge workflow
- [ ] Test suite running (2,500+ tests passing)
- [ ] Bug reproduction → fix cycle
- [ ] An audit session: Claude reading rules and filing gaps

### Diagrams/Graphics to create:
- [ ] **The commit timeline chart** — the exponential hockey stick curve (this is THE hero visual)
- [ ] Commits-per-day bar chart showing the acceleration
- [ ] Author breakdown pie chart (OisinRob / Claude / BigBobbo)
- [ ] Game phase flow diagram (Deployment → Command → Movement → Shooting → Charge → Fight → Morale)
- [ ] AI difficulty level comparison chart
- [ ] Architecture diagram: how the systems connect
- [ ] "Rules iceberg" — visible game vs hidden complexity
- [ ] Before/after feature comparison (Oct 2025 vs Mar 2026)

---

## THUMBNAIL/TITLE OPTIONS

**Thumbnail concepts:**
1. The commit graph hockey stick — flat line that goes vertical. Text: "WHAT HAPPENED?"
2. Split screen: janky early prototype / polished final game. Text: "6 MONTHS → 2 WEEKS"
3. Terminal with AI code scrolling + game screenshot overlay. Text: "1,067 COMMITS"
4. Close-up of the game board with units, dice, targeting lines. Text: "190,000 LINES OF AI CODE"

**SEO/Discovery tags:**
- AI coding, AI game development, Claude Code, vibe coding, AI programming
- Godot engine, strategy game, tabletop game
- Game dev diary, indie game development, solo game dev
- Before and after AI, AI acceleration, coding with AI

---

## IP SAFETY NOTE

Before publishing any content, the game should be rebranded to avoid Games Workshop IP issues:

**Must change:**
- Faction names (Space Marines → something original)
- Unit names and lore references
- Any GW-specific terminology

**Can keep (these are game mechanics, not IP):**
- Phase structure (Command, Movement, Shooting, Charge, Fight)
- All weapon keyword mechanics
- Wound allocation and save system
- Objective control and scoring
- The entire AI system
- All code architecture

The story is "I built a complex tabletop strategy game" — the specific IP doesn't matter to the narrative and removing it eliminates all risk.

---

## NEXT STEPS

1. **Record gameplay footage** — early prototype vs final game for comparison
2. **Record dev process footage** — terminal sessions, PR workflow, audit sessions
3. **Create the commit timeline chart** — this is the hero visual for the entire series
4. **Rebrand** — faction names, unit names, remove GW-specific lore
5. **Write hero video script** — use this outline as skeleton
6. **Create thumbnail** — test the hockey stick commit graph concept
7. **Edit hero video** — target 18-25 min
8. **Break into episodes** — release episode series alongside or after hero video
