# Dev Blog Content Outline
## "I Built a Complete Tabletop Strategy Game in 8 Days Using Only AI"

*Content plan for hero video + episodic breakdown*

---

## THE HOOK (Hero Video — 15-20 min)

**Title options:**
- "I Built a Full Strategy Game in 8 Days with AI — Here's What Happened"
- "AI Wrote 30,000 Lines of Code for My Game — And It Actually Works"
- "From Zero to Playable Strategy Game in 8 Days (AI Did the Coding)"

**Opening shot:** Side-by-side — empty Godot project on left, finished game with units moving, dice rolling, AI thinking on right. Text overlay: "8 days apart."

**The Pitch (first 60 seconds):**
> I don't really code. I gave an AI a 60-page tabletop wargame rulebook and asked it to build me a complete digital version — deployment, movement, shooting, charging, melee, morale, scoring, multiplayer, and an AI opponent that actually plays well. 215 commits later, here's what happened.

**Key stats to flash on screen:**
- 215 commits in 8 days
- 30,000+ lines of GDScript
- 1,200+ automated tests
- 82 distinct AI behaviors
- 5 complete game phases
- 30+ stratagems
- 15+ secondary missions
- Full multiplayer support

---

## NARRATIVE ARC — The 8-Day Story

### Act 1: "Can It Even Do This?" (Days 1-2, Feb 20-21)

**The setup.** Explain the challenge: tabletop wargames have *incredibly* complex rules. Movement coherency, weapon keywords, wound allocation priority, engagement ranges, line of sight, cover — it's a rules lawyer's paradise and a programmer's nightmare.

**What happened on Day 1 (6 commits):**
- AI shooting range consideration
- AI turn summary panel
- AI movement path visualization
- *The moment it clicked:* "Wait, the AI is already moving units and visualizing paths?"

**Day 2 explodes (41 commits):**
- Rapid Ingress stratagem
- AI speed controls
- Shooting target line visualization
- Multi-target charge declarations
- Fight selection dialog sync
- Desperate Escape mechanic
- Difficult terrain penalties
- One Shot weapons
- Stratagems (Go to Ground, Smokescreen)

**Narrative beat:** "By the end of Day 2, I had more game than I expected to have by Day 8."

**B-roll:** Screen recordings of early gameplay. The jank. The first time a unit charges and it works. First dice roll visualization.

---

### Act 2: "The Rules Are Fighting Back" (Days 3-4, Feb 22-23)

**The complications.** Show how tabletop rules create cascading complexity. You implement one thing and it breaks three others.

**Day 3 — The Bug Day (25 commits):**
- Duplicate function definitions broke the UI
- Game stuck at ROLL_OFF phase
- Multiplayer formations stuck
- Models not staying at dragged position
- But also: unit-specific abilities start landing (Martial Ka-tah, Swift Onslaught, Sentinel Storm, Throat Slittas)

**Day 4 — Feature explosion (49 commits — the busiest day):**
- Deadly Demise (exploding vehicles)
- Damaged profiles
- Waaagh! system for Orks
- Board rotation
- Secondary missions panel
- Overwatch dialog fixes
- Multiple unit ability implementations

**Narrative beat:** "Day 4 was the day I realized this wasn't a tech demo anymore. This was becoming a real game. 49 commits in a single day — the AI was implementing faction abilities, weapon keywords, and secondary missions faster than I could test them."

**Visual:** Time-lapse of the commit graph. Show the PRs piling up on GitHub.

---

### Act 3: "Making It Real" (Days 5-6, Feb 24-25)

**The polish phase.** Shift from "does it work?" to "does it feel right?"

**Day 5 (11 commits) — Integration day:**
- Merging 7 PRs
- AI deployment fixes for non-standard deployment zones
- Advance movement fixes

**Day 6 (21 commits) — UX overhaul:**
- Fullscreen game
- Terrain movement fixes (and reverting a bad wall climb penalty)
- Objective detection for non-circular bases
- Ruins movement correction
- Undo model movement fix
- Player scores display in top bar
- Primary mission selection in multiplayer lobbies
- Skip attacks on destroyed units

**Narrative beat:** "This is where it stopped feeling like an AI experiment and started feeling like something I wanted to play. The terrain system worked. The scoring tracked. Two armies on a board, trading shots, taking objectives."

**Visual:** Clean gameplay footage showing the UI improvements, objectives being captured, scores updating.

---

### Act 4: "The AI Gets Smart" (Days 7-8, Feb 26-27)

**The AI arc.** This is the video's climax. The AI goes from "random valid moves" to genuinely tactical play.

**Day 7 (26 commits) — The AI awakening:**
- Fix AI deep strike stalls
- Verbose AI thinking logs
- AI vs AI fight phase fixes
- AI decision-making improvements
- Skip UI dialogs for AI (it was opening popup windows for itself!)
- Verbose game logging

**Day 8 (13 commits) — Refinement:**
- Multiplayer deployment unification
- AI decision-making overhaul
- Advance movement bug fixes
- Enhanced game logging with dice rolls
- Stratagem feedback

**The AI difficulty ladder:**
1. Easy — random valid moves
2. Normal — full scoring with noise
3. Hard — stratagems + multi-phase planning
4. Competitive — zero noise, trade analysis, look-ahead

**Narrative beat:** "On Day 7, I watched two AI armies play a complete 5-round game against each other. The competitive AI was focus-firing wounded units, positioning for Rapid Fire range bonuses, using stratagems at the right moment, and pivoting to objective play in the late rounds. It had 82 distinct behaviors and I hadn't written a single one of them."

**Visual:** AI vs AI match footage. Highlight the AI thinking overlay. Show decision explanations in the game log. The charge arrows. The targeting lines.

---

### Act 5: "Ship It" (Day 9, Feb 28)

**The final push (23 commits):**
- Edge-to-edge coherency fix (rules accuracy)
- Unit Image Editor tool
- Character deployment fixes
- Reserves point cap correction
- Reserves destruction at Round 3
- Coherency distance display during placement
- Dialog size standardization
- Animated sprite system
- Comprehensive AI documentation

**Narrative beat:** "Day 9 wasn't about adding features. It was about getting the details right — edge-to-edge distance calculations instead of center-to-center, animated sprites, consistent dialog sizing. The kind of polish that separates a prototype from a product."

**Closing montage:** Full game being played. Deployment → Movement → Shooting → Charge → Fight → Morale → Scoring. The complete loop, working end to end.

---

## THE REFLECTION (Final 3-4 minutes)

### What Worked
- **The audit-driven workflow:** Write specs, let AI implement, audit results, file bugs, iterate. The PRPs (Product Requirement documents) were crucial.
- **Testing culture from Day 1:** 1,200+ tests meant the AI could refactor aggressively without breaking things.
- **Treating AI as a junior dev:** Give it clear specs, review its PRs, file bugs when it gets things wrong.

### What Didn't Work
- **Large files:** AIDecisionMaker.gd hit 15,000 lines. The AI built a monolith because it was easier than modularizing.
- **Cascading rule interactions:** Implementing one rule would subtly break another. The AI didn't always catch these regressions.
- **Multiplayer was fragile:** Many of the bug fixes in Days 5-7 were multiplayer sync issues the AI introduced.

### What It Means
- **Not "AI replacing developers"** — it's about amplifying ambition. One person + AI = a team's output.
- **The bottleneck shifted** from "writing code" to "knowing what to build." Game design knowledge and rules expertise mattered more than coding ability.
- **Code review is the new coding.** 80% of the work was reviewing AI output, testing it, and filing the next task.

---

## EPISODIC BREAKDOWN (4-6 episodes)

### Episode 1: "The Foundation" (Days 1-2)
*~10 min*
- Setting up the Godot project and explaining the rules
- How the AI-to-audit pipeline works
- First successful unit movement and combat
- End card: first AI turn playing out

### Episode 2: "The Rules Engine" (Days 2-3)
*~12 min*
- Deep dive into how 10th edition combat resolution works
- Weapon keywords: Blast, Rapid Fire, Melta, Lethal Hits, Devastating Wounds
- The wound allocation priority system
- Cover and line of sight
- Bug montage: all the ways rules can break each other

### Episode 3: "The AI" (Days 3-5)
*~15 min — longest episode, this is the draw*
- AI architecture: scoring functions, not neural networks
- Target priority: macro threat assessment + micro weapon allocation
- Movement AI: threat ranges, range band optimization, cover seeking
- Stratagem usage: when and why the AI uses Command Re-roll vs Fire Overwatch
- Demo: Easy vs Competitive AI playing the same scenario

### Episode 4: "Multiplayer & Polish" (Days 5-7)
*~10 min*
- WebRTC multiplayer implementation
- The deployment sync nightmare
- UI/UX improvements: dice visualization, floating damage, objective markers
- Secondary missions and the scoring meta-game

### Episode 5: "Shipping It" (Days 8-9)
*~8 min*
- Final rules audit against source material
- Animation and visual polish
- The Unit Image Editor bonus tool
- Final AI vs AI showcase match
- Lessons learned and what's next

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
- [ ] The commit graph / PR list on GitHub
- [ ] Code scrolling through AIDecisionMaker.gd (show the scale)

### Screen recordings of the dev process:
- [ ] Claude Code terminal sessions (the human-AI interaction)
- [ ] PR creation and merge workflow
- [ ] Test suite running (1,200+ tests passing)
- [ ] Bug reproduction → fix cycle

### Diagrams/Graphics to create:
- [ ] Day-by-day commit timeline infographic
- [ ] Game phase flow diagram (Deployment → Command → Movement → Shooting → Charge → Fight → Morale)
- [ ] AI difficulty level comparison chart
- [ ] Architecture diagram: how the systems connect
- [ ] "Rules iceberg" — visible game vs hidden complexity

---

## THUMBNAIL/TITLE OPTIONS

**Thumbnail concepts:**
1. Split screen: person at laptop looking overwhelmed / beautiful game screenshot. Text: "8 DAYS"
2. Terminal with AI code scrolling + game screenshot overlay. Text: "AI BUILT THIS"
3. Close-up of the game board with units, dice, targeting lines. Text: "30,000 LINES OF AI CODE"

**SEO/Discovery tags:**
- AI coding, AI game development, Claude Code, vibe coding, AI programming
- Godot engine, strategy game, tabletop game
- Game dev diary, indie game development, solo game dev

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

1. **Record gameplay footage** — clean full games at multiple difficulty levels
2. **Record dev process footage** — terminal sessions, PR workflow
3. **Rebrand** — faction names, unit names, remove GW-specific lore
4. **Write hero video script** — use this outline as skeleton
5. **Create thumbnail** — test 2-3 options
6. **Edit hero video** — target 15-20 min
7. **Break into episodes** — if hero video performs, release episode series
