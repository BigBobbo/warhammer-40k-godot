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
- **Commit gate.** `.claude/hooks/verify-windowed-gate.sh` blocks a commit that
  adds a ticked checkbox under `.llm/` unless a Godot windowed scenario
  (`40k/tests/scenarios/**.json`) is staged or the change is declared pure-state.
  The calc is a web app: its UI evidence is the Playwright run
  (`server/tests/e2e-calc.mjs`, real taps in Chromium, screenshots), which the
  gate does not know about. Do not fake either escape hatch. From stage 6 on the
  boxes below stay unticked and the status is written in words; the user decides
  whether that evidence counts (flag it in the final report). Stages 1-5 were
  ticked before the gate was noticed (staging and commit ran in one command, so
  the hook saw nothing staged); they were unticked again on 2026-11-20 so that
  every stage reads the same way. All eight stages are built, tested in a real
  browser and pushed; none is merged or deployed.
- Stage `git add` and run `git commit` in SEPARATE commands, so the gate sees
  what is staged.

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

Status 2026-11-20: all eight stages are built and pushed to
`ccr-213b28c6-sp0d05` (app version 1.99.0). Not merged, not deployed, no PR
open: the user decides (see Working agreements). Evidence at the last stage:
138 unit tests (`npm run test:calc`) and the Playwright run
(`tests/e2e-calc.mjs`).
Note: the user's instruction was delivered a second time at 07:04 UTC with the
same message id (re-queued by the worker restart at 06:33): a replay, not a new
request. Re-reading the plan it answered ("8. Rules data update") is what led
to the calculator-only refresh of v1.99.0.

- [ ] **1. Rule fixes** — BUILT in v1.91.0, browser-tested, pushed — end-of-battle VP exempt from the round cap; reserves
      8"; Plunging Fire chip; discard = +1CP wording.
- [ ] **2. Forecast you can trust** — BUILT in v1.92.0, browser-tested, pushed (MODEL in forecast.mjs, tests/calc-calibration.test.mjs) — attrition matters (dead units hold
      nothing, a weaker army holds and kills less); a per-game "how the battle
      goes" swing so margins match real games; kill rates from the calculator
      (matchup-aware) instead of a flat default; real-game card rates (10e
      equivalents, labelled) instead of a flat 50%; calibration test against
      the 11e numbers above; "what this forecast is built from" panel.
- [ ] **3. Find things / tablet** — BUILT in v1.93.0, browser-tested, pushed — Mission split into Plan / Cards / Play;
      tablet two-pane layouts; map-first Board with a unit strip on the phone.
- [ ] **4. Backup and restore** — BUILT in v1.94.0, browser-tested, pushed: file + 6-character transfer code via `POST/GET /api/calc-transfer` (sqlite, 1 h), persistent storage.
- [ ] **5. Less setup** — BUILT in v1.95.0, browser-tested, pushed (eventview.mjs, briefview.mjs, lists.mjs; board `reusablePlan()`) — event mode: my list pinned, opponent roster (paste
      many lists), layout letter per round, one tap to start a round; reuse my
      deployment against a new opponent; automatic matchup brief.
- [ ] **6. Decisions** — BUILT in v1.96.0, browser-tested, pushed (box not ticked: see
      "Commit gate" under Working agreements). Fixed-or-Tactical table on Cards
      (`modeParams()` / `modeHtml()`, worked out only when that view is open); going
      first vs second (already in the forecast hero); advice on each card in hand
      (`handHtml()`). Also fixed: destroyed units never reached the forecast (wrong
      army's list), Assassination with all characters dead, cards drawn this turn
      (`startDrawn`), 360 px phones (tabs / card table overflow; e2e now checks
      every view at 360 and 412 px).
- [ ] **7. Table tools** — BUILT in v1.97.0, browser-tested, pushed (box not ticked:
      see "Commit gate"). `playtools.mjs` (pure: clock, milestones, CP, turn log,
      undo; tests/calc-playtools.test.mjs) drawn by missionview.mjs `playView()`.
      CP per player (+1 each at "Turn done", discard CP once a battle round, 1CP card
      swap once a battle); round timer with the GW GT milestones or a chess clock
      (kept as end time: survives a reload; on the pinned line); Undo (30 steps,
      `remember()`); score sheet by battle round; turn checklist; battle ends after
      round 5; table mode (`m.table`: tracker only; Attack / Board closed in app.js);
      screen wake lock on Play (`syncWake()`); tablet: turn bar across the top, the
      two players side by side (CSS grid areas on `.mlay.play`).
      Not validated on a real device: the wake lock (refused in headless Chromium;
      the e2e uses a stand-in that counts the calls).
- [ ] **8. Rules data** — data stamp + points check BUILT in v1.98.0, browser-tested,
      pushed (box not ticked: see "Commit gate"). `adapter.mjs` `dataProvenance()` /
      `pointsCheck()` / `armyData()`; tests/calc-data.test.mjs. Each datasheet record
      carries its source: `source: "wahapedia-11e@<date>"` (this project's codex
      import: Space Marines / Space Wolves, Orks, Custodes, 16 and 21 Oct 2026) or
      the 40kdc `game_version.dataslate` (launch = 20 Jun 2026). The user's real
      Space Wolves list matches the data on all 12 datasheets.
      **Rules data update (v1.99.0), calculator only.** Measured 1.4.5 -> 1.5.1 bundle
      to bundle (scratch `dcdiff2.mjs`): NO unit stat line changed; points changed
      on 368 units; 598 weapons have other profiles; every ability / enhancement /
      stratagem id is re-keyed (4525 abilities added, 3909 removed) and the loadout
      format of all unit compositions changed. So the shared bundle is NOT swapped
      (it would take the 1.5.1 package code, a regenerated codex overlay and the
      game's data pipeline: a task of its own, needs the user's go-ahead).
      What keeps its key and shape IS taken, for the 20 factions without a codex
      import: points of 188 units and profiles of 104 weapons.
      `scripts/40kdc/gen_calc_errata.mjs <unpacked 1.5.1 package>` writes
      `server/public/calc/errata-data.mjs` (new value + hash of the bundle's value);
      `adapter.mjs applyErrata()` puts them on the records in place when the
      calculator loads (never on a record with a codex `source`, never when the
      hash differs, never on another bundle version). The Army Builder and the game
      do not import it (test: a process that loads store.js alone still has the
      bundle's values). Cross-check that 1.5.1 is the better release: where the two
      releases differ on Space Marines / Orks / Custodes, this project's Wahapedia
      import (16 / 21 Oct) agrees with 1.5.1 on 144 of 149 weapon stat lines and
      127 of 133 unit points (scratch `crosscheck.mjs`).
      Not taken: unit keywords (Grenades -> Explosives, Frame: the calc's stratagem
      texts use both names, no ground truth), units new in 1.5.1, weapons whose id
      changed, abilities. One weapon skipped for a new shape (Deathstrike, range N/A).
      Also added: the "Powered by 40kdc-data" credit on the calc page (the dataset
      licence asks for it on public deployments; only the builder page had it).

Ideas noted but not planned: exposure heat map; terrain set-up measurements;
coherency / legality inspector; post-game calibration from the user's own
logged games (the score sheet of 1.97 would feed it); line of sight in the
forecast's kill estimates; stratagems / CP in the forecast; layouts for
phones narrower than 360 px.
Done since this list was written: sync by code (1.94), player-edge setting (1.92).

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

## Round 3: rules audit (user: "Implement all in order", 20 Nov 2026)

The audit of 20 Nov found 11 places where the numbers disagreed with the 11th
edition rules, 6 new aids and 4 ease-of-use items. Status in words (no boxes
ticked: see "Commit gate" above). Rule texts: `core.txt` (Wahapedia, 20 Nov) and
the rules appendix (02.02.01 Modifiers, fetched the same day).

- Fix 1, charge odds (11.04): BUILT in v1.100.0, browser-tested. The target
  must be within the charge roll (and within 12") before the unit moves: need =
  ceil(gap), not gap - 2. Charge-roll modifiers add up (02.02.01 limits hit and
  wound rolls only); the roll cannot be more than 12.
- Fix 2, weapon choice: BUILT in v1.100.0, browser-tested. User asked for a
  GENERIC fix ("always, the optimal profiles are chosen"). `choose.mjs` scores
  every legal option with the calculator's own engine against the real target,
  then checks the pick with the whole unit's attack. Structure: one melee weapon
  per model (04.01), one profile per weapon and Hunter profiles (04.01.03),
  close-quarters weapons or the others (24.07), Extra Attacks (24.11), a ranged
  weapon need not be fired (04.02). Score = wounds removed - own expected
  Hazardous wounds. Proof: `tests/audit-weapon-choice.mjs` checks every datasheet
  (1,109) against 8 targets in both phases with an independent simulation; a
  sample of it runs with the unit tests. The first version failed 26 of 2,371
  checked choices, the second 15 of 6,065, both fixed (whole-unit pass; profiles
  on either side of "close-quarters or not"; optional Hazardous guns).
- Fix 3, detachment rules: BUILT in v1.100.0. Linked by `ability.detachment_id`
  (373 detachment records have no `detachment_rule_id`); codex records replace
  the provisional one. Parser reads "Attacks made by friendly X/Y/Z units have".
- Fix 4, wargear: BUILT in v1.100.0. "+1 W" (Storm Shield) on the carriers;
  wargear that is not in the list is listed switched off, not given to all.
- Engine: a hazard roll for every Hazardous weapon selected (24.15), also when
  the target was destroyed first.
- Fix 5, territory: BUILT in v1.101.0, browser-tested. `board.mjs objectiveSides`
  puts an expansion objective on the side of the territory polygon it is in
  (36 of 90 differed, 18 of 45 layouts). Unedited stored starting plans are
  migrated (`missionview.mjs migratePlanSides`, marker `sidesV`).
- Fix 6, objective control: BUILT in v1.101.0. Models carry their OC
  (`formation`), `planeval.ocInRange` sums the models in range, unit facts
  have `objOc`; a tie is nobody's (14.02).
- Fix 7, Hidden / Lone Operative: BUILT in v1.101.0. Light or dense features
  (errata), gone to ground 12", `threatTo({ detect })`, `planeval.detectRange`
  (Lone Operative always; Hidden only for units without guns, which never shoot).
- Fix 10, board checks: BUILT in v1.101.0. `planWarnings` rewritten (deployment
  zone, Infiltrators, Scouts, round 1, 6" edge band, enemy zone before round 3,
  Deep Strike exempt, 8" from enemies) and shown on the board per step;
  `coherentFormation` + `coherency` (03.03). `adapter.coreFlags` reads Deep
  Strike, Infiltrators, Scouts, Lone Operative, Stealth, Fights First, Deadly
  Demise and Firing Deck from the datasheet's core ability ids.
- Fix 11, cards: BUILT in v1.101.0 (Punishment off-turn via the existing
  fight-back kills, Delaying Action, Outflank, Purge and Secure, A Grievous
  Blow). Not changed: Consecrate still ignores kills in the opponent's turn.
- Also: a detachment's "+N" M" (Stormlance) is applied to the board unit's move.
- Fix 8, stratagem limits (15.01): BUILT in v1.102.0, browser-tested. One
  stratagem on a unit in a phase, each stratagem once in a phase (attacker
  cards and the target); Command Re-roll on a save for the defender
  (`rerollOneSave`: one failed save in the phase).
- Fix 9, abilities and hit modifiers: BUILT in v1.102.0. `weaponKw` keeps
  `required_target_keywords_any` / `excluded_target_keywords` as `limits`,
  `limitKw` switches them off per target (24.01). Engine: `heavyOk` (24.16),
  `damaged` (24.39), `engagedMV` + `engaged` (17.03), Psychic ignores harmful
  hit modifiers (24.29), no cap on save modifiers (02.02.01). Shooting type
  per attacker (10.04-10.06). Also: rules for named weapons
  (`rules.parseWeaponBullets`: Terminatus Assault, Full-throttle Assault - the
  only two in the data, both in the user's list) and enhancement grants
  (`adapter.enhancementGrants`: Wolf-Touched).
  Not done: Guile of the Wolf / Strategic Acumen doctrines beyond the chips
  (only one stratagem option reads a doctrine); Hammer Blow (a debuff on the
  enemy's later attacks); Imperium's Sword (its weapon text is cut off in the data).
