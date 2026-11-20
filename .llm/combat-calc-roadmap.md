# Combat Calc — review and roadmap (2026-11-20)

Phone/tablet web app at `server/public/calc` (deployed with `server/**` on merge
to main -> https://warhammer-40k-godot.fly.dev/calc/). 11th edition only.

The user asked for a step-back review (QoL, better projections, easier to use,
online research, tournament practice), answered four questions, then said:
**"implement these all in order, most valuable first; do not stop for
questions"** (2026-11-20). This file is the plan of record so the work survives
context compaction. Tick items as they land.

## Working agreements

- Branch `ccr-213b28c6-sp0d05`. Commit + push each finished stage. **Do not
  merge / deploy without the user's word** (they were told: reply "deploy as you
  go" to change that). One PR at the end is fine.
- Every player-facing stage: prepend `40k/data/version_history.json`, keep
  `server/public/calc/version.mjs` and the `sw.js` cache name in step
  (`tests/calc-version.test.mjs` checks all three).
- Tests per stage: `cd server && npm run -s test:calc` and
  `NODE_PATH=$(npm root -g) node tests/e2e-calc.mjs` (drives the real UI on a
  Pixel 7 profile, writes `tests/screenshots/`). Look at the screenshots.
- Never guess rules: check `https://wahapedia.ru/wh40k11ed/the-rules/core-rules/`
  or the Event Companion text. Label every modelling assumption in the UI.
- State migrations must be additive (never delete or rewrite the user's saved
  plans / lists in place).

## What the user told us

- Uses it: at home before the event, between rounds (after pairings), at the
  table mid-game. Two-day singles tournaments.
- Knows in advance: layout per round, all lists before the event, opponent at
  pairings.
- Pain: too much setup; not sure the numbers can be trusted; hard to find
  things. Buying an Android tablet (wants the space used), still uses the phone.

## Verified findings (measured in this repo or read in the primary source)

Forecast (`forecast.mjs`), before the changes below:
- Ignores army strength: 2000-pt list vs 1000-pt list = 48% / 83-83 VP.
- Dead units keep holding objectives in grid mode: A destroys 3 units a turn,
  B none -> B still ~75 VP and wins 26%.
- Too narrow: default mirror game mean ~75-82, SD ~9-10, margin p10/p90 +-20.
  **Real 11e GT games** (Stat Check, 94,739 player-games, launch to mid-Nov
  2026): mean 77.0, SD 21.1, P10/25/50/75/90 = 45/62/83/95/100, exactly 100 in
  15%, under 50 in 13%, winner 91.3 / loser 62.3, mean margin 29.8, the two
  scores correlate about -0.5, win chance 50% at ~85 VP (20% at 70-74, 43% at
  80-84, 84% at 90-94). First player wins 51.2% (+2.7 VP). Draws 2-3%.
- End-of-battle primary VP were cut by the 15-per-round cap (Event Companion
  v1.2 FAQ: they are exempt). Test: 42 where the rules give 44.
- `planeval.mjs` warned at 9" for reserves; 11e 20.04 is "more than 8"".
- Plunging Fire (22.05: +1 BS from a terrain section 3"+ high, or TOWERING
  within 12", vs a target with models on ground level) not in the calculator.
- Discarding a Tactical card at the end of your turn GAINS 1CP (any number of
  cards, 1CP total); events cap non-Core CP gain at 1 per battle round.
- No per-card 11e scoring data is public. 10e equivalents (Tabletop Battles,
  18,790 games, % completed by round R1-R5): Secure NML 82/87/84/79/78, No
  Prisoners 53/83/81/77/64, Centre Ground (Area Denial) 62/64/60/60/65, Cleanse
  69/67/62/68/73, Engage 48/73/70/63/67, Defend Stronghold -/67/62/62/88,
  Overwhelming Force 33/65/66/60/51, Bring It Down 37/63/58/48/39,
  Assassination 20/49/56/55/52, Tempting Target 48/49/41/38/47, Behind Enemy
  Lines 14/55/63/63/69, Forward Position (Storm Hostile) 0/62/61/57/53. None
  for Beacon, Outflank, Burden of Trust, Display of Might.

App / UX:
- Mission tab = 4.8 phone screens, 123 controls, in-game tracker at the bottom.
- Tablet 1280x800: 760 px centre column, ~40% unused, map below the fold.
- Board plans are keyed by layout + both lists (not reusable vs a new opponent).
- No backup / export / sync; no undo; no wake lock.
- Data: dataset `@alpaca-software/40kdc-data` 1.4.5 (17 Sep 2026); latest
  1.5.1 (13 Nov): 311 units' points changed, errata to 14 Oct. Layouts identical.

Tournament practice (Event Companion v1.2, GW GT pack, UKTC, WTC packs):
- Force Disposition is locked on the list; your primary = your FD x theirs;
  each FD pairing has layouts A/B/C and the organiser names the letter per
  round. Attacker/Defender by roll-off, secondaries chosen secretly, first turn
  rolled AFTER deployment (so plan for going first and second).
- GW GT: 5 games, 3h rounds, pace milestones (3h game: deployed with 2:35 left,
  rounds done at 1:55 / 1:15 / 0:45 / 0:25). UKTC: chess clock 1:25 each.
- WTC team pack bans apps that help in-game decisions (calculators named);
  UKTC gives private score apps no weight. GW GT pack names no calculator ban.
- Goonhammer (6 Nov 2026): secondaries usually max (cards never expire),
  100-98 games common, games are decided on primary; top players avoid
  Disruption.

Sources: Event Companion v1.2
https://assets.warhammer-community.com/eng_wh40k_event_companion-pl87i44rzn-a7ieny8i9x.pdf ·
core rules https://wahapedia.ru/wh40k11ed/the-rules/core-rules/ ·
Stat Check https://www.stat-check.com/the-meta ·
40k-analytics https://40k-analytics.github.io/stateofthegame/ ·
Tabletop Battles secondary stats
https://www.tabletopbattles.com/hammer-of-math-10th-edition-secondary-objective-statistics ·
Goonhammer https://www.goonhammer.com/40k-competitive-innovations-editorial-how-is-11th-edition-going ·
GW GT pack https://drive.google.com/file/d/1Ap9g6ZbNflGafN_OGpzeWqQPckB4vFRi/view ·
WTC pack https://wtc-belgium.com/wp-content/uploads/2026/06/2026-WTC40K-11th-edition-Event-Pack-v1.1.pdf

## Build order (most valuable first)

- [x] **1. Rule fixes** (v1.91.0) — end-of-battle VP exempt from the round cap; reserves
      8"; Plunging Fire chip; discard = +1CP wording.
- [x] **2. Forecast you can trust** (v1.92.0; MODEL in forecast.mjs, tests/calc-calibration.test.mjs) — attrition matters (dead units hold
      nothing, a weaker army holds and kills less); a per-game "how the battle
      goes" swing so margins match real games; kill rates from the calculator
      (matchup-aware) instead of a flat default; real-game card rates (10e
      equivalents, labelled) instead of a flat 50%; calibration test against
      the 11e numbers above; "what this forecast is built from" panel.
- [x] **3. Find things / tablet** (v1.93.0) — Mission split into Plan / Cards / Play;
      tablet two-pane layouts; map-first Board with a unit strip on the phone.
- [ ] **4. Backup and restore** (file), persistent storage.
- [ ] **5. Less setup** — event mode: my list pinned, opponent roster (paste
      many lists), layout letter per round, one tap to start a round; reuse my
      deployment against a new opponent; automatic matchup brief.
- [ ] **6. Decisions** — Fixed vs Tactical comparison; going first vs second;
      advice for the cards in hand (score / hold / discard for CP).
- [ ] **7. Table tools** — table mode (hide decision aids), pace clock with GW
      milestones + chess clock, end-of-turn checklist, CP, undo.
- [ ] **8. Rules data** — data date stamp; update the calc's dataset to 1.5.1.

Ideas noted but not planned: exposure heat map; terrain set-up measurements;
coherency / legality inspector; sync by code between devices; post-game
calibration from the user's own logged games; player-edge (skill) setting.

## Stage 2 notes (forecast model, v1.92.0)

- `forecast.mjs` `MODEL` holds every assumption. Calibrated on a FIELD of
  matchups (edge ~ N(0, 0.43), in-game swing SD 0.36): mean 77.3 (real 77.0),
  SD 20.4 (21.1), P10/50/90 46/82/100 (45/83/100), |margin| 29.8 (29.8), first
  player 51.1% +2.7 (51.2% +2.7), favourite wins 75% (pre-game rating: 69%).
  A single even matchup is narrower (mean ~83, SD ~15, |margin| ~21).
- Control is sampled at the end of every player turn (active player has the
  edge); Command-phase VP use the previous turn's snapshot (round 5: own turn).
- Kills: `P.fracs` (calculator, each unit on its best target, x MODEL.engage 0.3)
  when `killRate == null`; manual rate -> Poisson x left^killGamma; board plan
  with both armies -> `boardPlan.threats` (combined damage, normal approx).
- Position cards: estimate > board plan > own rating > REAL_RATES x cardPlay
  (1.4) > 50% x 1.4. Hold cards: plan, else "play for the card" at the real rate.
- Score-or-hold: partial payouts are held until round 4 (MODEL.holdUntil).
- Known limits: line of sight is not used in kill estimates; stratagems / CP
  are not modelled; a board plan only knows the units placed on it.
