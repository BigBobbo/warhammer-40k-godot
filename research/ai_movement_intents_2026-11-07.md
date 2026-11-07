# AI movement intents — full catalogue

_2026-11-07 · research for `40k/scripts/AIDecisionMaker.gd` movement decisions_

## What this is

Every distinct thing a unit might want to do with its move, for the AI to generate as candidate moves and score against each other. Today the AI mostly picks between going to an objective, holding one, Advancing to one, screening, attacking a melee target, and a few override checks. This list covers everything else found.

**How it was built:** seven research streams ran in parallel:

- 11e core rules (local rules text + engine)
- missions & secondaries
- the distilled YouTube learnings
- web search
- faction abilities & stratagems
- first-principles play by archetype
- a map of what the AI does today

That produced 489 raw candidates, which were deduplicated into 8 categories. Each category's editor re-checked the 11e rule claims against `docs/rules/40k_11th_edition_core_rules.txt` and checked what the AI does today against `AIDecisionMaker.gd` / `AIPlayer.gd`. After that, a completeness critic added missing intents and merged duplicates across categories, and a separate rules skeptic tried to disprove every rule claim.

**Limits (read these):**

- **YouTube:** the raw transcripts (`research/youtube/transcripts_text.jsonl.gz`, 1,029 videos) are not in this container — that file is not committed to git. The YouTube evidence comes from the distilled `research/youtube/ai_learnings.json` (31 findings, quotes checked against the transcripts).
- **Web:** during the research run web pages could not be opened (the session's network blocked wahapedia and similar sites), so web evidence is limited to search-result summaries. Most online tactics content is for 10th edition; anything only found there is labelled.
- **Errata check (after the run):** the network was then opened and the official 11e errata, FAQs and rules commentary were extracted from wahapedia into `docs/rules/40k_11th_edition_errata_faq_commentary.md` (the launch-PDF rules text lacks all of them). Every entry's rules claim was re-checked against that file: 50 corrected, 1 removed, 176 confirmed. Example: 13.09 Hidden now works in light **or** dense terrain.

## Totals

| | count |
|---|---|
| Intents (final) | 226 |
| AI today: none / partial / full | 112 / 106 / 8 |
| Value: high / medium / low | 64 / 104 / 58 |
| Rules check: verified / corrected / disputed / unverified | 141 / 82 / 0 / 3 |
| Rejected (illegal in 11e or noise) | 11 |
| Merged as duplicates across categories | 84 |

**Legend.** _AI today_: **none** = the AI never considers it; **partial** = only a score nudge, an override or a narrow case; **full** = the AI already generates it as a candidate move and picks it by score. _Rules_: **verified** = confirmed in a local 11e source; **corrected** = the rule detail was fixed; **disputed** = the editor and the skeptic disagree; **unverified** = no local source settles it.

## Your three examples

- **'Move into cover'. Main entry: SUR-03 (13.08 benefit of cover, -1 BS to the attacker). Vehicles and monsters: SUR-08 (hull-down). The stronger infantry form: SUR-01 (Hidden). Break line of sight completely: SUR-02. On an objective: OBJ-06 (absorbs MIS-15). Denial form: DEN-06 (absorbs OBJ-38). While keeping [HEAVY]: OFF-06. While shooting: OFF-N01. On arrival or disembark: TRN-10. Out of turn: ADJ-05 (reactive move) and ADJ-22 (pre-battle).** → `SUR-03` Move into cover (Benefit of Cover: attacker's BS worsened by 1), `SUR-08` Hull-down a vehicle or monster behind intervening terrain, `SUR-01` Move into light or dense terrain to become Hidden, `SUR-02` Break line of sight completely behind obscuring or Solid terrain, `OBJ-06` Move into cover on the objective: hold from a Hidden or obscured spot inside its terrain area, `DEN-06` Move into cover first to deny it: occupy the contested staging terrain (user example: move into cover), `OFF-06` Keep [HEAVY] while moving 3″ or less, `OFF-N01` Take the firing spot that sees the target but few enemy guns, `TRN-10` Set up out of sight, in cover or Hidden when arriving or disembarking (move into cover), `ADJ-05` Make a reactive move into cover or out of sight before their shooting (move into cover), `ADJ-22` Scout or Infiltrate into a Hidden or obscured forward post (move into cover, pre-battle)
- **'Move toward an enemy to shoot it'. Main entry: OFF-01. Supporting entries: sight line OFF-03; Hidden or Lone Operative targets OFF-04; half range and other bonus bands OFF-10; Advance with [ASSAULT] OFF-13; strip the target's cover OFF-17; safest firing spot OFF-N01. Target value from mission cards: OFF-14 (absorbs MIS-08). Shoot an objective holder off: OBJ-09. Shoot away screens: DEN-07. Kill-count cards: MIS-N01. Characters: OFF-15. From reserves or a transport: TRN-07, TRN-16.** → `OFF-01` Move toward an enemy to shoot it, `OFF-03` Open a sight line to the target, `OFF-04` Close inside detection range to unmask Hidden or Lone Operative targets, `OFF-10` Close to a bonus range band (half range, datasheet bands), `OFF-13` Advance and still shoot with [ASSAULT] weapons, `OFF-17` Flank to strip the target's cover, `OFF-N01` Take the firing spot that sees the target but few enemy guns, `OFF-14` Approach the enemy units your mission cards pay for, `OBJ-09` Move toward the enemy objective holder to shoot it off before the control check, `DEN-07` Move toward the enemy's screens to shoot or charge them away (user example: move toward an enemy to shoot it), `MIS-N01` Line up the turn's easiest kill when a card pays for kill count, `OFF-15` Hunt enemy characters (make the CHARACTER model visible or reachable), `TRN-07` Arrive from reserves to shoot (move toward an enemy to shoot it), `TRN-16` Drive a Firing Deck transport into firing position
- **'Move toward an enemy to charge it'. Main entry: OFF-02. Staging: out of Overwatch sight OFF-05 (merged into SUR-04); several targets in reach OFF-11; clean lane OFF-12; multi-unit charge OFF-16; strike first OFF-22; advance-and-charge OFF-23; Crushing Impact OFF-32; Waaagh! turn COO-06. Avoid Heroic Intervention: DEN-14 (absorbs OFF-24). Purpose-specific: card-paid targets OFF-14 (absorbs MIS-09); charge a holder off its objective OBJ-10; lock a shooter or actor DEN-03; tarpit a melee threat DEN-N01. From reserves or a transport: TRN-06, TRN-03. Pre-battle: ADJ-23.** → `OFF-02` Move toward an enemy to charge it, `OFF-05` (merged into `SUR-04` End the Movement phase out of Fire Overwatch reach), `OFF-11` Stage within reach of several charge targets, `OFF-12` Approach the charge target on a clean lane, `OFF-16` Set up a multi-unit charge, `OFF-22` Strike first: charge the enemy melee threat before it charges you, `OFF-23` Advance into charge range when a rule allows advance-and-charge, `OFF-32` Line up a Crushing Impact charge, `COO-06` Stage the Orks for one coordinated Waaagh! turn, `DEN-14` Stay out of enemy Heroic Intervention reach, `OFF-14` Approach the enemy units your mission cards pay for, `OBJ-10` Move toward the enemy objective holder to charge it off the objective, `DEN-03` Move toward a dangerous enemy shooter or action unit to charge and lock it (user example: move toward an enemy to charge it), `DEN-N01` Tarpit a dangerous enemy melee unit with a durable cheap unit, `TRN-06` Arrive from reserves to charge the same turn (move toward an enemy to charge it), `TRN-03` Tactical-disembark before the transport moves, then make the cargo's own move (keeps the charge), `ADJ-23` Scout or Infiltrate within turn-1 reach of the enemy (charge staging or aura range: move toward an enemy to charge it, pre-battle)

## At a glance

### Survival & concealment (25)

| ID | Intent | Move type | AI today | Value | Rules |
|---|---|---|---|---|---|
| SUR-01 | Move into light or dense terrain to become Hidden | Normal Move / Advance / Remain Stationary (already inside) / Disembark (tactical, then move) / Reserves arrival into a dense area | none | high | corrected |
| SUR-04 | End the Movement phase out of Fire Overwatch reach | End position of every move in our Movement phase (Normal / Advance / Disembark / Reserves arrival / Embark) | none | high | verified |
| SUR-02 | Break line of sight completely behind obscuring or Solid terrain | Normal Move / Advance / Fall Back (landing behind terrain) / Remain Stationary | partial | high | verified |
| SUR-03 | Move into cover (Benefit of Cover: attacker's BS worsened by 1) | Normal Move / Advance / Remain Stationary; a Normal Move of 3″ or less for [HEAVY] units | partial | high | corrected |
| SUR-05 | Stay outside enemy charge reach (kite) | Normal Move / Advance (break contact) / Fall Back (to a spot outside reach) | partial | high | verified |
| SUR-07 | Ordered Retreat out of a losing combat to a safe landing spot | Fall Back (Ordered Retreat) | partial | high | corrected |
| SUR-08 | Hull-down a vehicle or monster behind intervening terrain | Normal Move / Remain Stationary (a shuffle of 3″ or less for [HEAVY]) | partial | high | verified |
| SUR-09 | Stage as far forward as possible while out of line of sight | Normal Move / Advance (if it will not charge or act this turn anyway) | partial | high | verified |
| SUR-12 | Go dark: hold fire in light or dense terrain to keep or reset Hidden | Remain Stationary, or Normal Move into dense terrain, paired with skipping the unit in the Shooting phase | none | medium | corrected |
| SUR-19 | Stay outside distance-gated enemy bonus bands (half range, Explosives 8″, TOWERING 12″) | Normal Move / Advance / Remain Stationary | none | medium | verified |
| SUR-20 | Tuck the attached CHARACTER model where the main shooters cannot see it | Normal Move (per-model placement) | none | medium | verified |
| SUR-13 | Stand off outside enemy shooting reach (out-range or break contact) | Normal Move / Advance | partial | medium | verified |
| SUR-14 | Keep standalone characters out of sight or reach | Normal Move / Advance / Embark | partial | medium | verified |
| SUR-15 | Lone Operative: end beyond the range it can be seen from (12″ or X″) | Normal Move / Advance / Remain Stationary | partial | medium | corrected |
| SUR-17 | Choose Desperate Escape (or take to the skies) to escape through enemy models | Fall Back (Desperate Escape mode, or FLY taking to the skies) | partial | medium | corrected |
| SUR-22 | Shape the unit defensively: compact, near edge pulled back, all models in the area | Any move (per-model placement) | none | low | corrected |
| SUR-23 | Stay unseen by every enemy unit to deny indirect-fire spotting | Normal Move / Advance / Remain Stationary | none | low | verified |
| SUR-25 | Keep bystander units clear of melee scrums (more than 5″, at least more than 3″) | End positions of Normal / Advance moves (adjacent consequence: Fight-phase pile-in and consolidation) | none | low | corrected |
| SUR-26 | Keep friendly units more than 6″ from our own Deadly Demise models that may die | Normal Move / Advance | none | low | verified |
| SUR-27 | Hug the escort to keep a conditional Lone Operative | Normal Move (escort first, then the tethered unit) / Remain Stationary | none | low | verified |
| SUR-28 | Spend a temporary defensive buff: accept an exposed route this turn | Normal Move / Advance / Reserves arrival (a modifier on the survival terms of other moves) | none | low | verified |
| SUR-29 | Deny Surveil the Foe: stay unseen or beyond 18″ of surveillers, or shelter under our decoyed objectives | Normal Move / Advance / Remain Stationary | none | low | verified |
| SUR-30 | Perch infantry on a high terrain level out of reach of ground-bound enemies | Normal Move (vertical climb) | none | low | verified |
| SUR-N01 | Stay more than 6″ from enemy Deadly Demise models you are about to destroy | Normal / Advance end position, plus the choice of which unit charges the vehicle | none | low | verified |
| SUR-N02 | Keep an escape lane open behind units that may be charged | Normal / Remain Stationary (choice of end position) | none | low | verified |

### Shooting & charge setup (24)

| ID | Intent | Move type | AI today | Value | Rules |
|---|---|---|---|---|---|
| OFF-03 | Open a sight line to the target | Normal (3″ or less to keep [HEAVY], see OFF-06) | none | high | verified |
| OFF-04 | Close inside detection range to unmask Hidden or Lone Operative targets | Normal (Advance with [ASSAULT], OFF-13) | none | high | corrected |
| OFF-07 | Remain stationary to arm Indirect Fire and other stationary-gated shooting | Remain Stationary | none | high | verified |
| OFF-N01 | Take the firing spot that sees the target but few enemy guns | Normal (3″ or less for [HEAVY], see OFF-06); Advance with [ASSAULT]; a short shift instead of Remain Stationary | none | high | verified |
| OFF-01 | Move toward an enemy to shoot it | Normal | partial | high | verified |
| OFF-02 | Move toward an enemy to charge it | Normal (Advance only with an advance-and-charge rule, or to close in for next turn) | partial | high | corrected |
| OFF-06 | Keep [HEAVY] while moving 3″ or less | Normal (3″ or less for every model) or Remain Stationary | partial | high | corrected |
| OFF-11 | Stage within reach of several charge targets | Normal | none | medium | verified |
| OFF-16 | Set up a multi-unit charge | Normal | none | medium | verified |
| OFF-17 | Flank to strip the target's cover | Normal | none | medium | verified |
| OFF-19 | Spot for the gunline | Normal | none | medium | corrected |
| OFF-22 | Strike first: charge the enemy melee threat before it charges you | Normal (charge setup) | none | medium | verified |
| OFF-10 | Close to a bonus range band (half range, datasheet bands) | Normal | partial | medium | verified |
| OFF-12 | Approach the charge target on a clean lane | Normal | partial | medium | corrected |
| OFF-13 | Advance and still shoot with [ASSAULT] weapons | Advance | partial | medium | verified |
| OFF-14 | Approach the enemy units your mission cards pay for | Normal / Advance (with [ASSAULT]) / charge setup | partial | medium | verified |
| OFF-15 | Hunt enemy characters (make the CHARACTER model visible or reachable) | Normal (precision sight line) / charge setup | partial | medium | verified |
| OFF-23 | Advance into charge range when a rule allows advance-and-charge | Advance | partial | medium | verified |
| OFF-32 | Line up a Crushing Impact charge | Normal (charge setup) | none | low | verified |
| OFF-34 | Climb for Plunging Fire, or bring a TOWERING model within 12″ | Normal | none | low | corrected |
| OFF-37 | Route toward the marked quarry or oath target | Normal (approach / charge setup) | none | low | verified |
| OFF-39 | Make a normal move to arm move-gated buffs (Walking Fortress) | Normal | none | low | verified |
| OFF-33 | Fall back to re-charge or shoot when a rule allows it | Fall Back | partial | low | verified |
| OFF-35 | Ram a doomed Deadly Demise model into enemies | Normal (or charge) | partial | low | verified |

### Objective play & tempo (32)

| ID | Intent | Move type | AI today | Value | Rules |
|---|---|---|---|---|---|
| OBJ-06 | Move into cover on the objective: hold from a Hidden or obscured spot inside its terrain area | Normal Move (short reposition within range) / Remain Stationary | none | high | corrected |
| OBJ-01 | Hold objectives through the opponent's turn for your next Command-phase score | Remain Stationary (or a short Normal Move that keeps a model in range) | partial | high | verified |
| OBJ-03 | Contest an enemy-held objective to deny their next score and break their majority | Normal Move / Advance (also via Deep Strike or Rapid Ingress arrivals) | partial | high | verified |
| OBJ-04 | Go all-in on objectives in the final round | Advance / Normal Move | partial | high | corrected |
| OBJ-05 | Reinforce a contested or threatened objective to win the OC count | Normal Move / Advance | partial | high | verified |
| OBJ-07 | Flip an objective you did not control at the start of your turn | Normal Move / Advance / Reserves arrival | partial | high | corrected |
| OBJ-08 | Grab an objective for this turn's end-of-turn award even if you will lose it | Normal Move / Advance / Reserves arrival | partial | high | verified |
| OBJ-09 | Move toward the enemy objective holder to shoot it off before the control check | Normal Move (Advance only for [ASSAULT] weapons) | partial | high | corrected |
| OBJ-10 | Move toward the enemy objective holder to charge it off the objective | Normal Move (Advance only with an advance-and-charge ability) | partial | high | verified |
| OBJ-14 | Raid the opponent's home objective on the card's timing | Reserves arrival (Deep Strike / ingress) / Advance / Normal Move | partial | high | verified |
| OBJ-N01 | Play the last battle round by turn order | Second player: Advance / Normal / Reserves arrival. First player: Remain Stationary / Normal / screening. | partial | high | verified |
| OBJ-02 | Take an objective: move enough OC into its range | Normal Move / Advance | full | high | corrected |
| OBJ-12 | Garrison your home objective with the cheapest sufficient OC unit and push only part of the army | Remain Stationary / Normal Move | full | high | verified |
| OBJ-13 | Take and keep the central objective | Normal Move / Advance / Remain Stationary | full | high | verified |
| OBJ-15 | Toe in: put only the models you need into the objective area, from the side away from threats | Normal Move | none | medium | verified |
| OBJ-33 | Stand within objective range to switch on objective-gated abilities | Normal Move | none | medium | verified |
| OBJ-21 | Hand off an objective: move a cheap unit in so an expensive holder can leave | Normal Move (two units, in order) | partial | medium | verified |
| OBJ-22 | Flip an abandoned secured enemy objective | Normal Move / Advance / Reserves arrival | partial | medium | verified |
| OBJ-26 | Stage within one Normal move of next turn's scoring condition | Normal Move | partial | medium | verified |
| OBJ-27 | Advance now to pre-position when nothing is lost this turn | Advance | partial | medium | verified |
| OBJ-29 | Choose who commits first: bait with cheap holders or hang back so the opponent exposes first | Normal Move / Remain Stationary | partial | medium | verified |
| OBJ-17 | Steal an objective held only by battle-shocked enemies | Normal Move / Advance | full | medium | verified |
| OBJ-19 | Take the objective that completes a count threshold, not surplus ones | Normal Move / Advance | full | medium | verified |
| OBJ-34 | Stay locked on the objective: remain stationary while engaged to keep holding or contesting it | Remain Stationary (engaged), instead of Fall Back | full | medium | verified |
| OBJ-39 | Keep options open: end in central, flexible spots that reach two or more objectives next turn | Normal Move | none | low | verified |
| OBJ-41 | Bring the OC-granting character to the contested objective | Normal Move | none | low | verified |
| OBJ-43 | Shoot-and-scoot: take a forward firing position knowing a post-shooting move can reach an objective | Normal Move (plus an adjacent post-shooting reactive move) | none | low | verified |
| OBJ-46 | Keep a bombing lane open for strikes at the end of the opponent's Fight phase | Normal Move (AIRCRAFT) | none | low | corrected |
| OBJ-N02 | Anchor one model on the objective and stretch the rest toward the next job | Normal (per model; only some models move) | none | low | corrected |
| OBJ-N03 | Straddle two objectives with one unit | Normal / Advance | none | low | corrected |
| OBJ-42 | Buy the reach: pair the move with a move or advance boost when it turns 'one turn short' into 'arrives now' | Advance / Normal Move | partial | low | verified |
| OBJ-44 | Split a multi-model unit to cover more objectives, then spread the pieces | Normal Move (after a Command-phase or formations split) | partial | low | corrected |

### Mission actions & secondaries (27)

| ID | Intent | Move type | AI today | Value | Rules |
|---|---|---|---|---|---|
| MIS-01 | Stage a cheap action carrier with a Normal move, then keep it still | Normal (also Remain Stationary, Disembark rapid/tactical, Reserves arrival) | none | high | corrected |
| MIS-05 | Booby-trap as many untrapped terrain areas as you have spare units, objective areas first | Normal | none | high | verified |
| MIS-06 | Occupy an enemy-territory terrain area the enemy cannot get back into this turn | Normal (or Reserves arrival via Deep Strike) | none | high | corrected |
| MIS-02 | Send action carriers to different qualifying objectives | Normal | partial | high | verified |
| MIS-03 | Keep an action carrier and a separate OC holder on central every turn | Normal | partial | high | corrected |
| MIS-04 | Send the once-per-turn carrier to the best qualifying non-home objective | Normal | partial | high | verified |
| MIS-07 | Spread units into uncovered table quarters, wholly inside and clear of the centre | Normal / Advance / Reserves arrival | partial | high | verified |
| MIS-10 | Arrive from reserves straight onto mission geometry | Reserves arrival | partial | high | verified |
| MIS-23 | Get a Surveil carrier within 18in and sight of an unshielded enemy unit | Normal | none | medium | corrected |
| MIS-24 | End a real move within range of objectives that carry enemy operation markers | Normal / Advance | none | medium | corrected |
| MIS-25 | Be the only side in the last relic marker's terrain area | Normal / Advance | none | medium | corrected |
| MIS-26 | Put the planned killer on an objective before it kills | Normal (adjacent: Fight-phase consolidation, 12.08) | none | medium | corrected |
| MIS-12 | Get two units wholly inside the enemy deployment zone | Normal / Advance / Reserves arrival | partial | medium | corrected |
| MIS-13 | Outnumber the enemy wholly inside No Man's Land and stay there | Normal / Advance / Disembark | partial | medium | corrected |
| MIS-14 | Walk the Beacon unit out of your territory and keep it alive | Normal / Advance / Disembark | partial | medium | corrected |
| MIS-16 | Put a unit within 3in of the centre and keep enemies 6in away | Normal / Advance | partial | medium | verified |
| MIS-17 | Hug a battlefield edge outside your territory, with a partner on the opposite edge | Normal / Advance / Reserves arrival | partial | medium | unverified |
| MIS-18 | Plunder: move one cheap unit into a terrain area outside your territory | Normal (or Reserves arrival) | partial | medium | verified |
| MIS-19 | Hold the opponent's home or an expansion objective for Forward Position | Normal / Advance | partial | medium | unverified |
| MIS-21 | Take the objective the opponent named as your Tempting Target | Normal / Advance | partial | medium | verified |
| MIS-22 | Keep each Burden of Trust guard in range of its objective through the enemy turn | Remain Stationary / Normal (stay in range) | partial | medium | verified |
| MIS-28 | Prefer objectives inside the opponent's territory when the card pays a territory bonus | Normal / Advance | partial | medium | verified |
| MIS-30 | Advance into positional scoring geometry, never with a unit that must start an action | Advance | partial | medium | verified |
| MIS-N01 | Line up the turn's easiest kill when a card pays for kill count | Normal / Advance with [ASSAULT] / charge setup | partial | medium | verified |
| MIS-36 | Use a faction exemption to Advance, Fall Back or stay engaged and still start the action | Advance / Fall Back / Remain Stationary (engaged) | none | low | corrected |
| MIS-38 | Send a backup action carrier when the first is exposed to Overwatch | Normal | none | low | verified |
| MIS-35 | Fall back toward mission geometry instead of only away from the enemy | Fall Back | partial | low | verified |

### Screening, denial & opponent modelling (26)

| ID | Intent | Move type | AI today | Value | Rules |
|---|---|---|---|---|---|
| DEN-05 | Seal the screen's gaps against the widest enemy base | Normal (model layout within the move) | none | high | corrected |
| DEN-06 | Move into cover first to deny it: occupy the contested staging terrain (user example: move into cover) | Normal / Advance (adjacent pre-battle variant: Scout move 24.32, Infiltrators deployment) | none | high | corrected |
| DEN-07 | Move toward the enemy's screens to shoot or charge them away (user example: move toward an enemy to shoot it) | Normal / Advance (assault weapons) | none | high | verified |
| DEN-01 | Screen deep-strike and Rapid Ingress landing zones with 8″ denial bubbles | Normal (Remain Stationary once in place; adjacent pre-battle variant: Scout move / Infiltrators deployment) | partial | high | corrected |
| DEN-02 | Charge-screen a valuable unit (bubble-wrap it, with depth) | Normal (Remain Stationary when already in the lane) | partial | high | verified |
| DEN-03 | Move toward a dangerous enemy shooter or action unit to charge and lock it (user example: move toward an enemy to charge it) | Normal / Advance (Advance only with an advance-and-charge ability) | partial | high | corrected |
| DEN-04 | Move-block the enemy's approach corridors and the routes to your objectives | Normal | partial | high | verified |
| DEN-09 | Spoil the opponent's presence- or majority-based scoring zones | Normal / Advance / Reserves arrival (Deep Strike into their DZ) | none | medium | verified |
| DEN-10 | Don't end moves inside enemy 'ends a move within X″' triggers (reactive moves, snared objectives) | Normal / Advance (or Remain Stationary instead) | none | medium | corrected |
| DEN-12 | Hunt the enemy units that score from your half before the check | Normal / Advance | none | medium | verified |
| DEN-16 | Deny the opponent's kill-based scoring (don't offer their paying targets) | Normal / Remain Stationary / Fall Back | none | medium | verified |
| DEN-18 | Zone ground with your threat ranges (counter-punch posture) | Normal / Remain Stationary | none | medium | verified |
| DEN-19 | Fill a small terrain-objective area so enemy models can't end in it | Normal | none | medium | corrected |
| DEN-20 | Use dense terrain as a moat against enemy vehicles and monsters | Normal / Remain Stationary | none | medium | corrected |
| DEN-21 | Box in an enemy transport to spoil its passengers' disembark | Normal | none | medium | corrected |
| DEN-N01 | Tarpit a dangerous enemy melee unit with a durable cheap unit | Normal move to set up the charge; then Remain Stationary while engaged next turn | none | medium | verified |
| DEN-11 | Keep enemy units out of your deployment zone through their turn | Normal / Remain Stationary | partial | medium | corrected |
| DEN-14 | Stay out of enemy Heroic Intervention reach | Normal / Advance (and the charge-target choice) | partial | medium | corrected |
| DEN-23 | Bait or soak the enemy's one-shot reactions with a cheap unit first | Normal / Advance (sequenced before the key moves) | none | low | corrected |
| DEN-26 | Pin the enemy with fall-back-punishing units | Normal / Advance (toward the target to charge) | none | low | verified |
| DEN-27 | Stand within 3″ of a fight to dictate the enemy's consolidation | Normal (payoff in the Fight phase) | none | low | verified |
| DEN-28 | Remove enemy tokens and markers by ending a move next to them | Normal / Advance | none | low | verified |
| DEN-30 | Spread a picket net of Hidden infantry across separate terrain pieces | Normal / Advance (adjacent: Scout move, Infiltrators deployment) | none | low | corrected |
| DEN-34 | Hold ground inside enemy charge reach with a Fights First unit (corrected premise) | Normal / Remain Stationary | none | low | corrected |
| DEN-N02 | Wall enemy MONSTER/VEHICLE lanes with your own MONSTER/VEHICLE models | Normal / Remain Stationary | none | low | verified |
| DEN-25 | Block an engaged enemy's fall-back route (surround to trap) | Normal (adjacent: pile-in / consolidation wrap in the Fight phase) | partial | low | verified |

### Coordination, auras & abilities (32)

| ID | Intent | Move type | AI today | Value | Rules |
|---|---|---|---|---|---|
| COO-02 | Stay inside friendly buff auras and place the aura source to cover the most units | Normal / Advance (beneficiaries and source); Remain Stationary when already covered | none | high | corrected |
| COO-05 | Fall back to free the enemy for your guns and fresh chargers | Fall Back | none | high | verified |
| COO-01 | Converge several units on one priority target | Normal / Advance (Advance only for assault shooters or units allowed to charge after advancing) | partial | high | verified |
| COO-04 | Secure an objective at the end of your Movement phase, then move on | Normal / Advance onto the objective this turn (securing is not an action, so an Advance is fine); Normal / Advance away next turn | partial | high | verified |
| COO-06 | Stage the Orks for one coordinated Waaagh! turn | Normal (staging distance) this turn; Advance + charge in the Waaagh! turn | partial | high | verified |
| COO-11 | Park a Heroic Intervention umbrella | Normal / Remain Stationary in your own Movement phase; the payoff is adjacent (15.11, end of the opponent's Charge phase) | none | medium | verified |
| COO-12 | Post an Overwatch picket over the enemy's approach | Normal / Remain Stationary | none | medium | corrected |
| COO-17 | Push battle-shock and OC-debuff abilities onto enemy objective holders | Normal / Advance | none | medium | verified |
| COO-19 | Screen a key friendly with a SMOKE or cover-granting unit | Normal / Advance (screening unit); Normal (sheltered unit) | none | medium | corrected |
| COO-20 | End a Normal move within range of a proximity-damage ability | Normal (an Advance forfeits EXPLOSIVES and Bomb Squigs) | none | medium | verified |
| COO-26 | End the Movement phase Hidden to arm hidden-gated rules | Normal / Remain Stationary | none | medium | corrected |
| COO-27 | Take to the skies with FLY units to hop terrain and screens | Normal / Advance / Fall Back / Charge with take to the skies declared | none | medium | verified |
| COO-28 | Drive MONSTER/VEHICLE models straight through enemy infantry screens | Normal / Advance | none | medium | corrected |
| COO-31 | Bait and counter-punch: stage a retaliation unit behind a forward unit | Normal / Advance | none | medium | verified |
| COO-07 | End your move in range of the friendly unit your support ability should target | Normal (support model, at the start or end of its move), sequenced before the recipient's move | partial | medium | verified |
| COO-09 | Move as a mutually supporting group; do not arrive piecemeal | Normal / Advance (including deliberately short moves) | partial | medium | verified |
| COO-14 | Send OC-light or expendable units to positional cards; keep OC for objectives and actions | Normal / Advance | partial | medium | verified |
| COO-15 | Re-task battle-shocked units as bodies, not scorers | Normal / Advance (a Fall Back would be a forced Desperate Escape) | partial | medium | corrected |
| COO-16 | Pick destinations that satisfy several cards at once and split conflicting geometry | Normal / Advance | partial | medium | verified |
| COO-18 | Stay engaged on purpose | Remain Stationary (engaged) | partial | medium | verified |
| COO-22 | Clear lanes and sequence your own moves | other (move ordering for Normal / Advance / Disembark) | partial | medium | corrected |
| COO-29 | Use a move-through or MOBILE grant to shortcut models and terrain | Normal / Advance / Fall Back (Charge for Get Out da Way!) | partial | medium | verified |
| COO-N01 | Choose where the Advance goes after seeing the roll | Advance | partial | medium | verified |
| COO-33 | Stay within reach of a friendly enabler for reactive protection or extraction | Normal / Advance | none | low | corrected |
| COO-34 | Switch off enemy Overwatch with a denier during your Movement phase | Normal / Advance (the denier only needs to end in range before the phase ends) | none | low | corrected |
| COO-36 | Take the exposed direct lane with Overwatch-immune units | Normal / Advance / Disembark / Reserves arrival | none | low | verified |
| COO-37 | Arrive or disembark in sequence to share an arrival-triggered buff | Reserves arrival / Disembark (sequenced) | none | low | corrected |
| COO-38 | Slip past screens through their engagement range | Normal / Advance | none | low | verified |
| COO-40 | Rotate oval and FRAME bases for free reach or width | Normal / Advance / any move (rotation is free) | none | low | verified |
| COO-43 | Route a Thunderhawk over enemy units on a bombing run | Normal / Advance | none | low | verified |
| COO-45 | Shape the surge target with your end positions | Normal (own Movement phase positioning); adjacent: the Surge move (21.02) in the opponent's turn | none | low | verified |
| COO-N02 | Keep your own shooters' sight lines clear of your other units | Normal / Advance, plus move ordering | none | low | verified |

### Transports & reserves (26)

| ID | Intent | Move type | AI today | Value | Rules |
|---|---|---|---|---|---|
| TRN-04 | Delivery run: keep the cargo aboard and drive the transport to where the cargo's next task is | Normal / Advance (transport); the cargo stays embarked | none | high | verified |
| TRN-05 | Stay embarked, or embark, to protect a threatened unit and deny kills | Embark (after a Normal / Advance / Fall Back move), or stay embarked | none | high | corrected |
| TRN-02 | Drive the transport first, then Rapid-disembark the cargo where it must shoot, score or act | Normal (transport), then Disembark (rapid mode) | partial | high | verified |
| TRN-03 | Tactical-disembark before the transport moves, then make the cargo's own move (keeps the charge) | Disembark (tactical mode), then Normal / Advance | partial | high | corrected |
| TRN-06 | Arrive from reserves to charge the same turn (move toward an enemy to charge it) | Reserves arrival, then a charge in the Charge phase | partial | high | corrected |
| TRN-07 | Arrive from reserves to shoot (move toward an enemy to shoot it) | Reserves arrival | partial | high | corrected |
| TRN-09 | Bring every strategic-reserves unit in by the end of battle round 3 | Reserves arrival (adjacent: Rapid Ingress at the end of the opponent's round-3 Movement phase) | partial | high | verified |
| TRN-01 | Arrive from reserves onto an objective | Reserves arrival (ingress 20.04 / Deep Strike 24.09) | full | high | verified |
| TRN-10 | Set up out of sight, in cover or Hidden when arriving or disembarking (move into cover) | Reserves arrival / Disembark (where to set up) | none | medium | corrected |
| TRN-11 | Hold a unit in reserve this turn (keep the Rapid Ingress threat or a reactive answer) | Remain Stationary (in strategic reserves); adjacent: Rapid Ingress at the end of the opponent's Movement phase | none | medium | verified |
| TRN-14 | Combat-disembark out of an engaged or boxed-in transport | Disembark (combat mode) | none | medium | corrected |
| TRN-16 | Drive a Firing Deck transport into firing position | Normal (transport) / Remain Stationary | none | medium | verified |
| TRN-21 | Relocate a unit through strategic reserves (Da Jump, Teleport-shunter, Shokk Attack Engine) | other (ability: place in strategic reserves), then Reserves arrival | none | medium | verified |
| TRN-13 | Disembark to add a scoring or action unit | Disembark (rapid, or tactical + Normal) | partial | medium | verified |
| TRN-15 | Drive first, then assault- or shock-disembark (faction transport grants) | Normal / Advance (transport), then Disembark (assault 18.06 / shock 18.07) | partial | medium | corrected |
| TRN-17 | AIRCRAFT: choose a fresh ingress spot every turn | Reserves arrival (ingress only) | partial | medium | verified |
| TRN-18 | Arrive in the enemy backfield (deployment zone) where reserves normally cannot | Reserves arrival (Teleport Homer: adjacent, via Rapid Ingress) | partial | medium | verified |
| TRN-19 | Transport strike: deliver the cargo to kill a key target, accepting the squad's loss | Normal (transport) + Disembark (tactical / rapid / assault) | partial | medium | verified |
| TRN-20 | Ingress a loaded transport and Rapid-disembark the cargo the same turn | Reserves arrival (transport ingress), then Disembark (rapid) | partial | medium | verified |
| TRN-22 | Drop in during battle round 1 with a first-turn ingress grant | Reserves arrival (battle round 1) | partial | medium | verified |
| TRN-N01 | Bail out of a transport before it is destroyed | Disembark (Tactical, then a Normal move) / Disembark (Rapid, after the transport moves) | partial | medium | verified |
| TRN-23 | Embark a slow unit to taxi it (ride the transport this phase or next) | Normal / Advance, then Embark (the transport then makes a Normal / Advance move) | none | low | verified |
| TRN-24 | Fall back and embark to pull a unit out of combat | Fall Back, then Embark | none | low | verified |
| TRN-25 | Arrive as a blocker or denial screen | Reserves arrival | none | low | verified |
| TRN-26 | Park loaded transports where an emergency disembark is survivable | Normal (transport) / Remain Stationary | none | low | corrected |
| TRN-27 | Stage within 6″ or 9″ of an edge, unengaged, to keep an end-of-turn extraction | Normal / Advance (positioning); adjacent: return to reserves at the end of the opponent's Fight phase | none | low | corrected |

### Adjacent (outside the unit's own Movement phase) (34)

| ID | Intent | Move type | AI today | Value | Rules |
|---|---|---|---|---|---|
| ADJ-05 | Make a reactive move into cover or out of sight before their shooting (move into cover) | Normal move (09.05) granted reactively. Adjacent: opponent's Movement or Shooting phase. | none | high | corrected |
| ADJ-07 | Infiltrate or Scout a forward screen against enemy infiltrators, scouts and deep strikers | Infiltrators set-up (24.20) / Scout move (24.32). Adjacent: pre-battle. | none | high | verified |
| ADJ-01 | Counter-drop with Rapid Ingress into the gap the opponent's move left | Ingress move (20.04) via the Rapid Ingress stratagem. Adjacent: end of the opponent's Movement phase. | partial | high | verified |
| ADJ-02 | Infiltrate or Scout forward onto objectives that score in round 1 | Scout move (24.32) / Infiltrators set-up (24.20). Adjacent: pre-battle. | partial | high | verified |
| ADJ-03 | Wrap engaged enemies so their only way out is Desperate Escape | Charge move (11.04), pile-in (12.03), consolidation (12.08). Adjacent: Charge and Fight phases. | partial | high | verified |
| ADJ-04 | Consolidate into a fresh enemy unit to lock it (Engaging Consolidation) | Consolidation move, Engaging mode (12.08). Adjacent: Fight phase. | partial | high | corrected |
| ADJ-06 | Consolidate onto an objective (Objective Consolidation) in either player's Fight phase | Consolidation move, Objective mode (12.08). Adjacent: Fight phase, yours or the opponent's. | partial | high | verified |
| ADJ-08 | Decline consolidation when the forced mode would hurt you | Consolidation (12.08), declined. Adjacent: Fight phase. | none | medium | corrected |
| ADJ-13 | Rapid Ingress to score or deny at the end of the opponent's turn | Ingress move (20.04) via Rapid Ingress (15.07). Adjacent: end of the opponent's Movement phase. | none | medium | verified |
| ADJ-14 | Heroic Intervene onto the objective or terrain area the enemy is scoring from | Charge move (11.04) via Heroic Intervention (15.11). Adjacent: end of the opponent's Charge phase. | none | medium | corrected |
| ADJ-18 | Make a reactive move to body-block the mover's route | Normal move (09.05) granted reactively, or a reactive rapid disembark (18.04). Adjacent: opponent's Movement phase. | none | medium | corrected |
| ADJ-19 | Shape the charge move's end positions for what comes next | Charge move (11.04). Adjacent: Charge phase. | none | medium | verified |
| ADJ-21 | Use Objective Consolidation to slide out of sight or charge reach while staying on the objective | Consolidation move, Objective mode (12.08). Adjacent: Fight phase. | none | medium | corrected |
| ADJ-22 | Scout or Infiltrate into a Hidden or obscured forward post (move into cover, pre-battle) | Scout move (24.32) / Infiltrators set-up (24.20). Adjacent: pre-battle. | none | medium | corrected |
| ADJ-23 | Scout or Infiltrate within turn-1 reach of the enemy (charge staging or aura range: move toward an enemy to charge it, pre-battle) | Scout move (24.32) / Infiltrators set-up (24.20). Adjacent: pre-battle. | none | medium | verified |
| ADJ-24 | Shoot, then move out of sight or out of charge reach (post-shooting move) | Normal move (09.05) granted after shooting. Adjacent: your own Shooting phase. | none | medium | corrected |
| ADJ-09 | Heroic Intervention (Leap to Defend) into a unit that just charged | Charge move (11.04) via Heroic Intervention (15.11). Adjacent: end of the opponent's Charge phase. | partial | medium | corrected |
| ADJ-10 | Counter-charge to lock a dangerous shooter or action unit before your turn (Into the Fray, NO ESCAPE) | Charge move (11.04) via Heroic Intervention Into the Fray (15.11) or NO ESCAPE. Adjacent: opponent's Charge or Movement phase. | partial | medium | corrected |
| ADJ-16 | Make a reactive move out of the triggering enemy's charge reach | Normal move (09.05) granted reactively. Adjacent: opponent's Movement phase. | partial | medium | verified |
| ADJ-17 | Make a reactive move onto an objective (grab it, or retake it after they disengage) | Normal move (09.05) granted reactively. Adjacent: opponent's Movement or Shooting phase. | partial | medium | corrected |
| ADJ-20 | Overrun slingshot: extra pile-in into a second enemy when your target dies before you fight | Pile-in move (12.03) as part of an Overrun fight (12.06). Adjacent: Fight phase. | partial | medium | corrected |
| ADJ-25 | Remove casualties (and coherency breakers) to improve the unit's position | Casualty or coherency removal (05.04, 03.03), in any phase. Adjacent: not a move, but it repositions the unit's footprint. | partial | medium | verified |
| ADJ-26 | Pull a doomed unit off the board into strategic reserves (escape) | Repositioned to strategic reserves (20.02), later an ingress move (20.04). Adjacent: end of the opponent's Fight phase, or end of your turn. | partial | medium | corrected |
| ADJ-27 | Declare formations and deploy so the army works whether it goes first or second | Deployment set-up and formation declarations (18.01, 20.01, 23.01). Adjacent: pre-battle. | partial | medium | unverified |
| ADJ-28 | Pile in to bring more models into the fight | Pile-in move (12.03). Adjacent: Fight phase, yours or the opponent's. | full | medium | verified |
| ADJ-29 | Decline or limit the pile-in to keep objective range or avoid a second engagement | Pile-in move (12.03), declined or partial. Adjacent: Fight phase. | none | low | verified |
| ADJ-31 | Redeploy after both armies are set up, to answer the opponent's deployment | Redeployment set-up (deployment rules re-applied). Adjacent: pre-battle. | none | low | verified |
| ADJ-32 | Hold Scouts in reserve and set them up in your zone after seeing the enemy deployment | Set-up from strategic reserves under 24.31. Adjacent: pre-battle. | none | low | corrected |
| ADJ-37 | Place emergency-disembarked passengers where they survive | Emergency disembark move (18.05), forced. Adjacent: any phase. | none | low | corrected |
| ADJ-30 | Pull an idle or stranded unit into reserves to re-drop where it matters (reposition) | Repositioned to strategic reserves (20.02), then an ingress move (20.04). Adjacent. | partial | low | verified |
| ADJ-33 | Shoot, then step onto an objective (post-shooting move) | Normal move (09.05) granted after shooting. Adjacent: your own Shooting phase. | partial | low | verified |
| ADJ-34 | Move again at the end of the Fight phase: leave a losing fight or reposition | Normal or fall-back move (09.05 / 09.07), or Objective consolidation (12.08) via a rule. Adjacent: end of a Fight phase. | partial | low | verified |
| ADJ-35 | Re-embark outside your Movement phase for protection or redelivery | Embark (18.02) granted at the end of the Fight phase, or after a reactive normal move. Adjacent. | partial | low | corrected |
| ADJ-36 | Use rule-granted surge moves on your terms (and pre-position so the closest enemy is the right target) | Surge move (21.02). Adjacent: usually the opponent's Shooting phase. | partial | low | verified |

## Suggested implementation order

| # | ID | Intent | Effort | Mechanism | Why |
|---|---|---|---|---|---|
| 1 | COO-18 | Stay engaged on purpose | S | Override in _decide_engaged_unit (AIDecisionMaker.gd:11958), before the default 'Not on objective or better to fall back — fall back' branch (:12123). Compare staying with leaving. Stay value: melee damage the unit deals in our own Fight phase (finish the enemy); lock value if the engaged enemy is in phase_plan.lock_targets or is an action/objective unit; shield value for non-MONSTER/VEHICLE units that would otherwise sit in many enemy weapon ranges; close-quarters shooting value for MONSTER/VEHICLE units (10.06). Leave value: what the unit can still do after falling back (no shooting, charge or actions unless it has a Fall Back and X rule), minus Desperate Escape hazards if it is battle-shocked. Feed in the already computed survival.recommendation (:12410-12416), which nothing reads today. | Off an objective the AI always falls back when it can. It abandons fights it is winning and releases its own lock charges (F015/F017), and every input the fix needs already exists in this function. |
| 2 | OFF-07 | Remain stationary to arm Indirect Fire and other stationary-gated shooting | S | New override in _select_movement_action next to the T7-26 Heavy check (AIDecisionMaker.gd:7419). If a ranged weapon's special_rules contains 'indirect fire' (the same string parse _get_unit_heavy_weapon_data uses for 'heavy', :13571) and its best target is not visible, return REMAIN_STATIONARY unless an objective is reachable this move. Give units that can see that target a spotter bonus in _assign_units_to_objectives, and move them before the battery in _build_move_order (:7666). Shooting side: stamp shooting_type 'indirect' (RulesEngine.gd:6560 notes that no AI path does). | RulesEngine already applies the 10.07 rule: a stationary unit with a friendly spotter fails only on 1-3 instead of 1-5 (RulesEngine.gd:6594-6604). The AI has zero references to indirect fire, so one override roughly triples the battery's hits on targets it cannot see. |
| 3 | OFF-06 | Keep [HEAVY] while moving 3″ or less | S | In the T7-26 branch (AIDecisionMaker.gd:7419-7430; _should_hold_for_heavy_bonus :13618), generate a 3″-or-less alternative with _compute_movement_toward_target(unit, …, 3.0, …) toward cover, the objective area's edge or a sight line, counting vertical distance. Take it when it gains cover, OC or line of sight without losing the Heavy targets; otherwise REMAIN_STATIONARY as today. | The AI already decides to keep [HEAVY] but then freezes. 24.16 allows a 3″ move (40k_11th_edition_core_rules.txt:3751-3765), often enough to reach cover or the objective footprint. |
| 4 | OBJ-N01 | Play the last battle round by turn order | S | Give _get_round_strategy_modifiers (AIDecisionMaker.gd:17421) a moves_last_in_battle flag from snapshot.meta.first_turn_player, the same source _enemy_next_turn_round uses (:9812). Last mover in round 5: survival about 0, threat, Overwatch and Hidden terms off, Advance freely, force reserve arrivals. First mover in round 5: keep survival and add weight to end-of-battle and end-of-opponent-turn rows (already released by FIX_EOG_TIMING, :22830), plus screening of the objectives those rows need. | Rounds 4 and 5 share one profile that raises survival to 1.4 (:2724) for both seats, yet the player who moves last is the one for whom survival is worth nothing. |
| 5 | SUR-03 | Move into cover (Benefit of Cover: attacker's BS worsened by 1) | M | Replace _position_has_cover (AIDecisionMaker.gd:14858), which only asks whether any enemy-to-position line crosses any terrain polygon, with a probe-formation call to TerrainManager.unit_has_cover_11e(probe_unit, attacker_model) (TerrainManager.gd:1388) against the 2-3 strongest enemy shooters in range. Widen _find_cover_path (:14817) beyond ±15/30°. Add a cover_gain term next to the F001/F004 terms in _assign_units_to_objectives (:10290-10313), scaled by incoming ranged threat and zeroed against [IGNORES COVER]. | Benefit of cover (-1 BS on every incoming ranged attack, F030) is the most frequent defensive gain in 11e, and the current check is not the 13.08 rule. |
| 6 | OBJ-06 | Move into cover on the objective: hold from a Hidden or obscured spot inside its terrain area | M | In the hold paths of _select_movement_action, HOLD DECISION (AIDecisionMaker.gd:7187) and OBJ-GAP-1 'already on it' (:7346), sample short repositions inside the hosting terrain area that keep the unit's OC in range (_ai_model_in_objective_range :13145). Score them with the SUR-03 cover probe and _position_would_be_hidden (:28515). Emit BEGIN_NORMAL_MOVE when one beats standing still and the Heavy and indirect gates allow it. | Objective holders are the most-shot units (F028). Because the terrain area is the objective, better protection inside it costs no OC. |
| 7 | SUR-05 | Stay outside enemy charge reach (kite) | M | New generator replacing the AI-TACTIC-4 'avoiding charge threat — staying to shoot' REMAIN_STATIONARY (AIDecisionMaker.gd:7357-7391). For ranged units, sample endpoints within M that keep at least one target in range (_get_enemies_in_weapon_range :13760) and maximise the margin beyond each enemy melee unit's reach from _calculate_enemy_threat_data (:28695). Correct that reach to M+12″, plus D6 where an advance-and-charge rule applies. Choose by margin × target value. | The AI already detects charge danger but can only freeze or walk in. Kiting reuses the existing threat data. |
| 8 | COO-05 | Fall back to free the enemy for your guns and fresh chargers | M | Second branch in _decide_engaged_unit (AIDecisionMaker.gd:11958). If the engaged enemy is a high-value non-MONSTER/VEHICLE unit, friendly unengaged shooters' expected damage (from the shooting-phase estimators) is at least its remaining wounds, and our engaged unit is cheap and not needed for OC (oc_without_us is already computed there), return BEGIN_FALL_BACK via _compute_fall_back_destinations (:12185), landing clear of the gunline's lanes. | An engaged non-MONSTER/VEHICLE unit cannot be targeted by shooting (04.02 requires an unengaged target), so a cheap tarpit currently shields the enemy's best unit from the AI's guns. It lives in the same function as item 1. |
| 9 | OFF-03 | Open a sight line to the target | M | Make _find_firing_position_toward_objective (AIDecisionMaker.gd:13848) and _clamp_move_for_weapon_range (:13780) check visibility to the target's models with probe models through TerrainManager.model_visible_11e (TerrainManager.gd:1209). Score the firing_position term (:10250-10268) on visible targets rather than centroid range. OFF-N01's exposure count is the follow-up on the same probe. | In 11e an obscuring area blocks a sight line completely, so centroid range overstates what the unit can shoot. A sight-line-aware endpoint is the base layer for every shooting intent. |
| 10 | SUR-04 | End the Movement phase out of Fire Overwatch reach | M | Rework _overwatch_exposure_penalty (AIDecisionMaker.gd:28660). Test visibility with probe models (TerrainManager.model_visible_11e) instead of the 24″ band alone. Skip it when the opponent has no CP or no unengaged, non-battle-shocked, non-TITANIC shooter, and for Overwatch-immune units. Price only the single worst newly exposed target per phase, since Fire Overwatch can be used once per phase (15.01). Then enable OVERWATCH_EXPOSURE_PENALTY through a profile and re-run the paired A/B. | The term already exists but is switched off because its range-only approximation over-taxes movement. Making it faithful to the rule is what lets it pay off (F004). |
| 11 | MIS-N01 | Line up the turn's easiest kill when a card pays for kill count | S | Read MissionManager._kills_this_turn_11e (MissionManager.gd:3270) and the opponent's last-turn kill count into _build_primary_awareness (AIDecisionMaker.gd:22800). While a destroy-1+, kill-more or per-unit row is unmet this turn, add a kill-probability term (remaining wounds vs expected damage) to _build_phase_plan charge_intent (:3773), to the firing-position choice, and to _calculate_target_value (:17642), replacing the flat ×1.15 kill_pressure multiplier (:17879). | Five Purge the Foe primaries (plus No Prisoners) pay 3-4 VP per turn for one sure kill, and the engine already tracks the counts. |
| 12 | SUR-01 | Move into light or dense terrain to become Hidden | M | Add a Hidden-spot candidate generator for units with no scoring job (the pass-3 fallback in _assign_units_to_objectives, AIDecisionMaker.gd:11651) and for forward staging. Sample points in nearby light/dense terrain areas reachable this move; keep those where _position_would_be_hidden (:28515) holds; rank by _hidden_immunity_fraction (:28548, fixed to use the per-observer detection_range_inches_for) and by forward progress. Pair it with HIDDEN_FORFEIT_PENALTY so the units do not shoot the benefit away, then re-run the mirror A/B. | F001 is implemented only as a bias on which objective to walk to, which is why it measured flat. The engine's errata-correct Hidden predicate (TerrainManager.gd:1001-1052) is ready to use. |

## Details

Per-intent details (description, when to use, unit types, rules basis with corrections, current AI coverage, engine support, value, evidence) are in [`ai_movement_intents_2026-11-07_details.md`](ai_movement_intents_2026-11-07_details.md).

## Appendix A — Rejected

| Category | Intent | Rejected by | Reason |
|---|---|---|---|
| survival | Bait Fire Overwatch with a cheap model or unit moved first (a sub-intent mentioned inside youtube#3, web#5 and first-principles#6) | bucket editor | This is a 10e-only trick from the Balance Dataslate's per-move Overwatch timing. In 11e Fire Overwatch is used once, at the end of the opponent's Movement phase, after every move has been made (15.08, docs/rules/40k_11th_edition_core_rules.txt:2735-2747; the engine offers no per-move Overwatch at 11e, 40k/phases/MovementPhase.gd:1745-1749), so a bait move draws nothing. All three raw candidates say not to generate it. The surviving intent is SUR-04. |
| denial | Sacrificial Overwatch soak: move a cheap unit first to draw out the enemy's Overwatch | bucket editor | Illegal premise in 11e. FIRE OVERWATCH (15.08, 40k_11th_edition_core_rules.txt:2735-2768) is used only at the END of the moving player's Movement phase, by one unengaged unit that snap-shoots one visible enemy unit within 24″ of the overwatching player's choosing; there is no per-move trigger to bait, so the overwatcher waits and picks the best target after every move (once per phase, 15.01 :2495-2500; engine note StratagemManager.gd:5077-5080: “exactly one timing at 11e (no per-move / set-up / charge-declaration offer; those were 10e Balance Dataslate wording)”). The corpus agrees: “You can't play around it any more — big squads just get overwatched” (ai_learnings.json disagreements[2], Deploy on the Line 40K FT5JoL5Myis @05:00). The legitimate remainder, ending out of sight or beyond 24″ of enemy Overwatch units, belongs to survival (B37 Overwatch exposure). Listed because the bucket definition names it; first-principles#71 itself flagged it as impossible in 11e (its reactive-move bait half is DEN-23). |
| coordination | Bait out the enemy's Fire Overwatch with a cheap unit before the real threat moves | bucket editor | Illegal premise in 11e. Fire Overwatch is used at the END of the opponent's Movement phase against any visible, unengaged enemy within 24″ (15.08/15.09, 40k_11th_edition_core_rules.txt:2735-2768), and each stratagem can be used only once per phase (15.01, :2495-2499). The opponent chooses after seeing every move, so the order of your moves cannot draw it out. The corpus agrees: YouTube qahZnQPN8a8 @27:00 (Vanguard Tactics, F004): 'Overwatch is so powerful in this game now because you can't ... put one model out ... you can't bait them out anymore'. web#10 itself flagged this. The legal variant, baiting a once-per-phase reactive MOVE, is kept as COO-35. |
| transport_reserves | Combat-disembark to add OC to an objective | bucket editor | Illegal in effect. A combat disembark leaves the unit battle-shocked (18.04 AFTER MOVING, 40k_11th_edition_core_rules.txt:3055-3056), and a battle-shocked unit's OC is '-' and it cannot start actions (:213-221). It cannot add OC. The rest of the candidate (escape, or join the fight) is kept in TRN-14. |
| transport_reserves | Embark the Beacon unit and keep scoring it | bucket editor | The Beacon card lets a unit be designated while embarked, but it scores only 'if the beacon unit is on the battlefield' (40k/data/40kdc/missionCards.json:2850). Embarked units are not on the battlefield (40k_11th_edition_errata_faq_commentary.md:36; engine MissionManager.gd:1772-1780). The protect-by-embarking intent is kept in TRN-05, with the Beacon exclusion. |
| adjacent | Consolidate straight back out of line of sight (free step-back consolidation) | bucket editor | Illegal as a free move in 11e. 12.08's modes are mandatory and assessed in order (Ongoing, Engaging, Objective). With no enemy and no objective within 3″, the unit has no consolidation mode and can't move (40k_11th_edition_core_rules.txt:1942-1958; ConsolidationMove.gd:1-20, :126). The legal version, moving within the selected objective's range, is kept as ADJ-21. |
| adjacent | Overrun slingshot toward an objective | bucket editor | Illegal. The overrun fight's extra move is a pile-in. Its moved models must end closer to the closest pile-in target, and the unit must end engaged (12.03 AFTER MOVING, 40k_11th_edition_core_rules.txt:1737-1766; 12.06 :1866-1877). Only the slingshot into a second enemy unit (ADJ-20) is legal. |
| adjacent | Set emergency-disembarked passengers outside the transport's Deadly Demise radius | bucket editor | Not possible. 18.05 and its errata require each model to be wholly within 6″ of the destroyed transport and as close as possible to it (40k_11th_edition_core_rules.txt:3061-3078; 40k_11th_edition_errata_faq_commentary.md:609). 24.08 resolves Deadly Demise after the emergency disembark, against every unit within 6″ of that model (:3670-3699). The placement intent itself is ADJ-37. |
| adjacent | Make a reactive move with a stratagem, then Fire Overwatch with the same unit | bucket editor | Illegal within one phase. Under 15.01, unless otherwise stated, a player can't target the same unit with more than one stratagem in the same phase (40k_11th_edition_core_rules.txt:2500-2501). RESPONSIVE TACTICS-style moves and Fire Overwatch are both used in the opponent's Movement phase, and its end is part of that phase (09.03, :1368-1370). Reactive moves granted by datasheet abilities are not stratagems, so that variant is kept in ADJ-11. |
| adjacent | Shoot the unit that just fell back (RAPID REACTIONS) | bucket editor | Not a movement decision. It is a reactive shooting stratagem (.llm/codex_11e_wahapedia/custodes/RULES.md:211) and belongs to shooting target selection. The AI scores it 2.2 (CustodesCodexMovement.gd:259-260). The movement parts of factions#50 are kept in ADJ-17 (WHILE THEIR BACKS ARE TURNED) and ADJ-10 (NO ESCAPE). |
| denial | Snare the objective the enemy must step onto (MORTIS SNARES) [DEN-29] | errata check | Commentary 01.02.02 says a rule that specifies when it is triggered but not how long it is active is only active for that period. MORTIS SNARES (WHEN: end of your Movement phase) prints no duration, as RULINGS.md:402 itself notes and unlike stratagems that state one (e.g. DEATH BEGETS VENGEANCE: 'hated until the end of the battle'). The snare therefore lapses at the end of your Movement phase and cannot catch next turn's contester; at most it catches an opponent's Rapid Ingress arrival in that same end step, which must still be more than 8″ from your units. The engine's 'lasts until triggered' ruling contradicts the commentary; it holds only if 'That objective is no longer snared' is deliberately read as a duration. — Commentary 01.02.02 Persisting Rules Effects (errata doc :28); MORTIS SNARES text at .llm/codex_11e_wahapedia/space-marines/wahapedia/Stratagems.csv:92 |

## Appendix B — Merged duplicates

- `SUR-11` Pick the Hidden spot behind a dense wall and beyond each shooter's detection range → merged into `SUR-01` (SUR-11 refines SUR-01: it picks which spot inside the Hidden area to use (Gone to Ground −3″, outside the shooters' detection range). That is a scoring detail of the same 'end Hidden' generator, not a separate purpose.)
- `OFF-05` Stage the charge out of sight to avoid Overwatch → merged into `SUR-04` (Both end the Movement phase where no eligible enemy can Fire Overwatch on the unit. OFF-05 only adds the constraint 'stay inside charge reach of the target'.)
- `OFF-20` Kite: shoot from outside the enemy's charge reach → merged into `SUR-05` (Same purpose: end beyond enemy charge reach. OFF-20 only adds the constraint 'keep a target in weapon range'.)
- `OBJ-11` Stage for next turn's strike: end out of the enemy's reach and sight but inside your own next-turn reach → merged into `SUR-09` (Both stage forward, out of enemy sight and reach, but inside our own reach for next turn.)
- `COO-32` Keep Lone Operative spacing while staying in your own range → merged into `SUR-15` (Both keep an unattached Lone Operative beyond the 12″/X″ range it can be seen from. COO-32's 'stay in own weapon range' is a constraint on the same move.)
- `COO-39` Escape a wrap by falling back through enemy models → merged into `SUR-17` (Same fall-back choice: when wrapped, use Desperate Escape or take to the skies to pass through enemy models.)
- `SUR-06` Stay engaged as a shield from enemy shooting (decline to fall back) → merged into `COO-18` (All are one decision: Remain Stationary while engaged. They differ only in the value term: shield from shooting, falling back forfeits the turn, keep the enemy locked, M/V keeps close-quarters shooting. COO-18 already lists these. The merged entry should also state 'stay to finish a fight you are winning'. OBJ-34 stays separate because its trigger is objective OC and it is already implemented.)
- `SUR-18` Stay locked in combat when falling back would forfeit the turn → merged into `COO-18` (All are one decision: Remain Stationary while engaged. They differ only in the value term: shield from shooting, falling back forfeits the turn, keep the enemy locked, M/V keeps close-quarters shooting. COO-18 already lists these. The merged entry should also state 'stay to finish a fight you are winning'. OBJ-34 stays separate because its trigger is objective OC and it is already implemented.)
- `DEN-15` Stay engaged to keep an enemy unit locked (decline to fall back) → merged into `COO-18` (All are one decision: Remain Stationary while engaged. They differ only in the value term: shield from shooting, falling back forfeits the turn, keep the enemy locked, M/V keeps close-quarters shooting. COO-18 already lists these. The merged entry should also state 'stay to finish a fight you are winning'. OBJ-34 stays separate because its trigger is objective OC and it is already implemented.)
- `OFF-09` Stay engaged with a MONSTER/VEHICLE and keep shooting → merged into `COO-18` (All are one decision: Remain Stationary while engaged. They differ only in the value term: shield from shooting, falling back forfeits the turn, keep the enemy locked, M/V keeps close-quarters shooting. COO-18 already lists these. The merged entry should also state 'stay to finish a fight you are winning'. OBJ-34 stays separate because its trigger is objective OC and it is already implemented.)
- `SUR-10` Hide the units the enemy's kill cards pay for → merged into `DEN-16` (All deny the opponent's kill VP by not offering paying targets: by unit type (SUR-10), by location such as objectives or trapped areas (OBJ-23), or by pulling a doomed unit out of reach (OBJ-24).)
- `OBJ-23` Keep fragile units off objectives and terrain areas the opponent is paid to kill them on → merged into `DEN-16` (All deny the opponent's kill VP by not offering paying targets: by unit type (SUR-10), by location such as objectives or trapped areas (OBJ-23), or by pulling a doomed unit out of reach (OBJ-24).)
- `OBJ-24` Pull a doomed unit out of reach to deny the opponent's kill VP → merged into `DEN-16` (All deny the opponent's kill VP by not offering paying targets: by unit type (SUR-10), by location such as objectives or trapped areas (OBJ-23), or by pulling a doomed unit out of reach (OBJ-24).)
- `SUR-16` Embark into a transport to take the unit off the battlefield → merged into `TRN-05` (Same move: embark after a Normal or Advance move to take a threatened unit off the battlefield.)
- `SUR-21` Fall back straight into a transport → merged into `TRN-24` (Same move: fall back, then embark, to leave a combat.)
- `SUR-31` Hide behind a large model or a SMOKE unit → merged into `COO-19` (Two halves of one intent: unit X sheltered by unit Y's models. SUR-31 moves the sheltered unit, COO-19 moves the screen. The merged entry must cover a plain big-model sight-line wall as well as SMOKE. Engine caveat: LoS ignores models, and the 11e Smokescreen 'screened unit' clause is not applied (see other_gaps).)
- `SUR-24` Keep non-chargers more than 6″ from unengaged enemy units (Into the Fray) → merged into `DEN-14` (All avoid enemy Heroic Intervention. SUR-24 keeps non-chargers more than 6″ away (Into the Fray). OFF-24 picks charge targets with no unengaged neighbours. DEN-14 covers both modes plus the target choice.)
- `OFF-24` Pick on isolated targets → merged into `DEN-14` (All avoid enemy Heroic Intervention. SUR-24 keeps non-chargers more than 6″ away (Into the Fray). OFF-24 picks charge targets with no unengaged neighbours. DEN-14 covers both modes plus the target choice.)
- `OFF-08` Tie up a dangerous shooter → merged into `DEN-03` (Same purpose: charge an enemy shooter or action/objective unit and stay engaged, to switch off its normal shooting and its actions.)
- `OFF-21` Lock the enemy's action or objective unit in melee → merged into `DEN-03` (Same purpose: charge an enemy shooter or action/objective unit and stay engaged, to switch off its normal shooting and its actions.)
- `OFF-29` Fall back to free an engaged enemy for your shooters → merged into `COO-05` (Identical: fall back so the engaged enemy becomes a legal target for our guns and fresh chargers.)
- `OFF-26` Drive a Firing Deck transport into a firing position → merged into `TRN-16` (Identical: position a Firing Deck transport.)
- `OFF-27` Take to the skies over screens and walls → merged into `COO-27` (Identical: FLY units take to the skies to cross screens and walls.)
- `OFF-28` Clear the screen that blocks your charges or landing zones → merged into `DEN-07` (All remove the enemy screen that blocks our charges, landing zones or objectives. COO-10's 'use a cheaper unit first' is the sequencing rule of the same intent.)
- `COO-10` Clear the enemy screen with a cheaper unit first → merged into `DEN-07` (All remove the enemy screen that blocks our charges, landing zones or objectives. COO-10's 'use a cheaper unit first' is the sequencing rule of the same intent.)
- `MIS-08` Move toward the enemy unit your cards pay for, to shoot it → merged into `OFF-14` (MIS-08 and MIS-09 are OFF-14 split into shoot and charge. The distinct purpose is valuing targets by what our cards pay; the approach itself is OFF-01/OFF-02.)
- `MIS-09` Move toward the enemy unit your cards pay for, to charge it → merged into `OFF-14` (MIS-08 and MIS-09 are OFF-14 split into shoot and charge. The distinct purpose is valuing targets by what our cards pay; the approach itself is OFF-01/OFF-02.)
- `OFF-41` Shoot or fight from inside objective range (Purge and Secure) → merged into `MIS-26` (Identical: for Purge and Secure, make the kill from within objective range.)
- `COO-03` Spot for your indirect fire → merged into `OFF-19` (COO-03 (spot for indirect fire) is clause (a) of OFF-19 (spot for the gunline).)
- `COO-24` Advance into charge reach when an ability allows a charge after advancing → merged into `OFF-23` (Identical: Advance, then charge, under an advance-and-charge grant.)
- `COO-41` Set up a Crushing Impact charge → merged into `OFF-32` (Identical: set up a Crushing Impact charge.)
- `COO-44` Ram a dying Deadly Demise vehicle into enemy clusters → merged into `OFF-35` (Identical: ram a doomed Deadly Demise model into enemies.)
- `OFF-31` Move EXPLOSIVES/GRENADES units within 8″ without advancing → merged into `COO-20` (OFF-31 (bring EXPLOSIVES within 8″ with a Normal move) is one case of COO-20 (end a Normal move in range of a proximity-damage ability).)
- `OFF-36` Stay inside a friendly offensive aura → merged into `COO-02` (OFF-36 (stay in a friendly offensive aura) is a subset of COO-02 (stay inside buff auras and place their source).)
- `OFF-38` Bait a surge with surge-capable melee units → merged into `COO-45` (All shape which enemy is 'closest' when a surge move fires: for our surge units (OFF-38) and for the enemy's (DEN-24). ADJ-36 stays separate as the execution of the surge itself.)
- `DEN-24` Be the lightning rod for enemy surge moves → merged into `COO-45` (All shape which enemy is 'closest' when a surge move fires: for our surge units (OFF-38) and for the enemy's (DEN-24). ADJ-36 stays separate as the execution of the surge itself.)
- `OFF-18` Arrive from reserves in charge position → merged into `TRN-06` (Identical: arrive from reserves just over 8″ away and charge the same turn.)
- `OFF-30` Arrive from reserves in a firing position → merged into `TRN-07` (Identical: arrive from reserves in a firing position.)
- `OFF-25` Disembark tactically so the unit can still charge → merged into `TRN-03` (Identical: Tactical Disembark before the transport moves, so the unit can still charge.)
- `OBJ-38` Occupy the key mid-board staging terrain first → merged into `DEN-06` (Identical: occupy the mid-board staging terrain first (F005).)
- `MIS-15` Move into cover or Hidden on a scoring spot that must survive the enemy turn → merged into `OBJ-06` (Same intent: take the most protected spot that still scores. MIS-15 only extends it from objectives to card scoring spots.)
- `DEN-08` Contest the objectives the opponent's cards need to control → merged into `OBJ-03` (Both contest an objective to block the opponent's control-based scoring, whether a primary row or a card/action completion check.)
- `MIS-11` Deny the opponent's mission scoring with your own moves → merged into `DEN-09` (MIS-11 is the umbrella 'break the opponent's card conditions'. Its zone/presence part is DEN-09; its objective-contest part goes to OBJ-03.)
- `OBJ-25` Keep enemy units out of your deployment zone and territory → merged into `DEN-11` (Identical: keep enemy units out of our deployment zone and territory through their turn.)
- `MIS-37` Kill enemy units that sit inside your deployment zone or territory → merged into `DEN-12` (Identical: kill the enemy units that score from our half before the check.)
- `OBJ-18` Use battle-shocked units as bodies, not scorers → merged into `COO-15` (Identical: give battle-shocked units body jobs, not scoring jobs.)
- `COO-08` Rotate a cheap holder onto an objective to free a combat unit → merged into `OBJ-21` (Identical: hand an objective to a cheap holder so the expensive unit can leave.)
- `OBJ-16` Secure an objective, then walk the unit on to the next one → merged into `COO-04` (Identical: secure the objective (14.03), then release the unit.)
- `OBJ-40` Project battle-shock onto the enemy objective holder, then step on → merged into `COO-17` (Identical: push battle-shock and OC debuffs onto the enemy holder, then step on.)
- `OBJ-28` Stage several units for a coordinated strike turn (once-per-battle army buff, e.g. Waaagh! War Cry) → merged into `COO-06` (Same staging for a once-per-battle strike turn. COO-06 is the Waaagh! case and OBJ-28 the general one; keep one entry with the general trigger.)
- `OBJ-30` Concentrate force on a subset of objectives or refuse a flank → merged into `COO-09` (Both concentrate force or refuse a flank instead of arriving piecemeal.)
- `COO-23` Plan Advances around advance re-rolls and fixed advance results → merged into `OBJ-42` (Both plan reach with the real, modified Advance distribution (bonuses, re-rolls, fixed results).)
- `MIS-29` Stage this turn for card geometry you can only reach next turn → merged into `OBJ-26` (Identical: for cards kept in hand, stage within one move of next turn's scoring condition.)
- `OBJ-20` Push onto objectives in the opponent's territory when a card pays a territory bonus → merged into `MIS-28` (Identical: prefer objectives in enemy territory when the card pays a territory bonus.)
- `OFF-40` Set up an Overwatch net → merged into `COO-12` (All four leave unengaged volume shooters with sight lines over the enemy's approach, ready to Fire Overwatch in the opponent's turn.)
- `OBJ-45` Set an Overwatch / crossfire net for the opponent's turn → merged into `COO-12` (All four leave unengaged volume shooters with sight lines over the enemy's approach, ready to Fire Overwatch in the opponent's turn.)
- `ADJ-11` Leave volume shooters where they can Fire Overwatch on the enemy's approach → merged into `COO-12` (All four leave unengaged volume shooters with sight lines over the enemy's approach, ready to Fire Overwatch in the opponent's turn.)
- `OBJ-35` Consolidate onto an objective after fighting (adjacent: Fight phase) → merged into `ADJ-06` (Identical: Objective Consolidation onto an objective.)
- `OBJ-36` Rapid Ingress onto an open objective (adjacent: end of the opponent's Movement phase) → merged into `ADJ-01` (Identical: counter-drop by Rapid Ingress onto an open objective.)
- `OBJ-31` Time the reserves: hold arrivals for round 3 or for Rapid Ingress → merged into `TRN-11` (Both decline this turn's arrival to keep a later or Rapid Ingress option, including waiting for round-3 access to the enemy deployment zone.)
- `OBJ-37` Scout or Infiltrate onto, or within one move of, an objective (adjacent: pre-battle) → merged into `ADJ-02` (All use Scouts, Infiltrators or deployment to start on early-scoring geometry (objectives or card zones).)
- `MIS-34` Deploy, infiltrate and scout toward the geometry your early cards pay for → merged into `ADJ-02` (All use Scouts, Infiltrators or deployment to start on early-scoring geometry (objectives or card zones).)
- `OBJ-32` Park the transport for next turn's tactical disembark and charge → merged into `TRN-04` (OBJ-32 (park the transport for next turn's tactical disembark and charge) is one case of TRN-04's delivery run.)
- `MIS-20` Control two No Man's Land objectives at the end of your turn → merged into `OBJ-19` (Secure No Man's Land is already one of OBJ-19's threshold examples.)
- `MIS-27` Time the grab of the enemy home objective for the end-of-battle check → merged into `OBJ-14` (Both time the raid on the enemy home objective to the card's check, including end-of-battle rows.)
- `MIS-32` Gather Intel round 1: get a unit onto the central objective → merged into `OBJ-13` (Gather Intel's round-1 central award is one of OBJ-13's central-objective payoffs.)
- `COO-13` Give the action to the cheapest unit that can reach it and still meet its completion condition → merged into `MIS-01` (Same action-carrier intent, one generator: COO-13 picks the cheapest carrier, MIS-01 stages it.)
- `TRN-08` Arrive to score a positional secondary (enemy deployment zone, flank edge, empty quarter, No Man's Land) → merged into `MIS-10` (All set arriving reserves up on mission geometry this turn: positional cards or action sites.)
- `TRN-12` Arrive at an action site and start the action the same turn → merged into `MIS-10` (All set arriving reserves up on mission geometry this turn: positional cards or action sites.)
- `MIS-31` Disembark at the scoring spot in a mode that keeps the unit scoring → merged into `TRN-13` (Both disembark to add a scoring or action unit; MIS-31's choice of disembark mode is part of the same intent.)
- `ADJ-12` Use Rapid Ingress as the last arrival window before the end-of-round-3 reserve wipe → merged into `TRN-09` (Both beat the end-of-round-3 reserve wipe; ADJ-12 is its Rapid Ingress branch.)
- `COO-25` Redeploy with a repositioning ability when the VP math is positive → merged into `TRN-21` (Same: use a reposition-to-reserves ability (Da Jump, Teleport-shunter and the like) when the VP math is positive. ADJ-26 and ADJ-30 stay separate because they use the end-of-opponent-turn extraction timing.)
- `COO-21` Stay outside enemy ability trigger radii → merged into `DEN-10` (Both end moves outside enemy 'ends a move within X″' triggers. COO-21 adds debuff auras to the same radius check.)
- `COO-35` Bait the enemy's once-per-phase reaction with a cheap unit first → merged into `DEN-23` (Identical: soak the enemy's once-per-phase reaction with a cheap unit first.)
- `COO-30` Build a kill zone over an objective or approach lane → merged into `DEN-18` (Both project overlapping threat over the ground the enemy must take next turn; COO-30 is the multi-shooter crossfire form.)
- `DEN-31` Bait with an expendable unit to pull an enemy unit out of position → merged into `COO-31` (Identical: bait, then counter-punch.)
- `ADJ-15` Park counter-chargers within Heroic Intervention reach of where the enemy will charge or score → merged into `COO-11` (Identical: in our own Movement phase, park units where they can Heroic Intervene.)
- `DEN-32` Use your own reactive move to body-block or screen, not only to dodge → merged into `ADJ-18` (Identical: use a reactive move to body-block.)
- `COO-42` Use move-after-shooting abilities to reposition → merged into `ADJ-24` (Identical: reposition with a move granted after shooting.)
- `DEN-17` Arrive by Rapid Ingress (or from reserves) to deny the opponent's end-of-turn scoring → merged into `ADJ-13` (All use Rapid Ingress at the end of the opponent's Movement phase to meet or break end-of-their-turn checks. MIS-33's Heroic Intervention clause belongs to ADJ-14; its Overwatch clause is a target choice, not a move.)
- `MIS-33` In the opponent's turn, break their action or end-of-turn scoring with reactive moves → merged into `ADJ-13` (All use Rapid Ingress at the end of the opponent's Movement phase to meet or break end-of-their-turn checks. MIS-33's Heroic Intervention clause belongs to ADJ-14; its Overwatch clause is a target choice, not a move.)
- `DEN-33` Heroic Intervention to contest an objective or shield a unit → merged into `ADJ-14` (Identical: Heroic Intervene onto the objective or area the enemy is scoring from.)
- `DEN-13` Deny strategic-reserve board-edge arrivals (cover the 6″ edge bands) → merged into `DEN-01` (Same purpose: deny enemy reserve arrivals. DEN-13's 6″ board-edge bands must survive as DEN-01's strategic-reserves sub-generator.)
- `DEN-22` Drive a MONSTER/VEHICLE through an enemy infantry screen → merged into `COO-28` (Identical: drive MONSTER/VEHICLE models through enemy infantry screens (17.01).)

## Appendix C — Other gaps the critic noticed

- Off an objective, an engaged unit always falls back when it can (AIDecisionMaker.gd:12123). _assess_engaged_unit_survival computes a 'hold' recommendation (:12410-12416) that nothing reads. So the AI leaves fights it is winning and releases its own lock charges (affects COO-18, DEN-03 and DEN-N01).
- No 'what if I stood here' query for visibility or cover. _can_shooter_see_target (AIDecisionMaker.gd:190) takes unit IDs; F004 is a 24″ range band (:28648-28656); _position_has_cover (:14858) is a polygon-crossing proxy. TerrainManager already accepts probe model dicts (model_visible_11e :1209, model_fully_visible_11e :1215, unit_has_cover_11e :1388, is_model_hidden :1001). One shared, memoised _probe_unit_at(unit, dests) would unlock SUR-02/03/04/08, OFF-03/04/17/N01, OBJ-06 and TRN-10.
- Engine line of sight ignores models: EnhancedLineOfSight.gd:27 is terrain-only, and TerrainManager.gd:1221-1224 says so. Rule 06.01 ignores only the observing and observed units' own models, so other units should block. The 11e SMOKESCREEN entry declares covers_screened (StratagemManager.gd:5106), but only the SMOKE unit itself receives the cover flags (StratagemManager.gd:1918-1927). The COO-19/SUR-31 walls and COO-N02 have no in-engine payoff until this is modelled.
- Threat model (_calculate_enemy_threat_data, AIDecisionMaker.gd:28695). Charge reach is M + 12″ + engagement range, but 11.04 only needs the target within the roll, so the +2″ over-estimates. It ignores advance-and-charge grants, FLY and terrain. Shooting reach is weapon range with no enemy move, so SUR-13 (out-ranging) and SUR-19 (distance bands) cannot be scored.
- Candidate structure: movement candidates are (unit, objective) pairs plus screen, corridor and attack slots (_assign_units_to_objectives :9834; pass 3 :11438), and the per-unit overrides only bend the heading toward the objective. Intents whose destination is not an objective need a generic positional-candidate generator scored in the same currency: SUR-01/02/09 staging, COO-02 aura spots, OFF-19 spotter spots, COO-11/COO-12 pickets, DEN-18 zones and OFF-N01 firing angles.
- The movement plan is rebuilt only when a friendly unit becomes movable or moves again (need_plan, AIDecisionMaker.gd:6948-6985). Enemy reactive moves (F014), Rapid Ingress arrivals and Overwatch casualties mid-phase never trigger a re-plan.
- Stale text. AIDecisionMaker.gd:2589-2591 quotes the pre-errata 13.09 ('dense' only), but TerrainManager.is_model_hidden already applies the light/dense errata (TerrainManager.gd:1031-1052), so the engine side of the Hidden fix is done. AIDecisionMaker.gd:2648-2652 says Fire Overwatch fires per move, but at edition 11+ MovementPhase.gd:1746-1752 offers it only at the end of the opponent's Movement phase. The errata check has since corrected SUR-01, SUR-12, OFF-04 and OBJ-06: Hidden needs light or dense terrain (Gone to Ground still needs intervening dense terrain).
- _hidden_immunity_fraction (AIDecisionMaker.gd:28548-28575) measures 15″ centroid-to-centroid using detection_range_base_inches, not the per-observer detection_range_inches_for (TerrainManager.gd:1069) its comment promises, so Gone to Ground (SUR-11) is never valued.
- The AI never embarks mid-battle. EMBARK_UNIT exists in the engine (MovementPhase.gd:465/555, _validate_embark_unit :9120), but the AI's embark scoring runs only at formations (AIDecisionMaker.gd:4637-4690), so TRN-05, TRN-23 and TRN-24 cannot happen. Separately, the engine's embark check uses disembarked_this_phase (MovementPhase.gd:9143), while 18.02 bars any unit set up on the battlefield this turn, including reserve arrivals.
- The AI has no reference at all to [INDIRECT FIRE] (zero matches in AIDecisionMaker.gd, AIPlayer.gd and AIAbilityAnalyzer.gd) and selects no shooting type (RulesEngine.gd:6560), so OFF-07, OFF-19 and SUR-23 have no hook.
- Screening (pass 3, AIDecisionMaker.gd:11438-11550) runs whenever the enemy has reserves (_get_enemy_reserves :14884), with no gate on when they can actually arrive: no ingress in round 1 (20.03), no Rapid Ingress in round 1 (15.07), and the enemy's CP. Round-1 screens for the first player are wasted units. The same CP gate is missing from the Overwatch term.
- Advance planning uses M+2 in _select_movement_action (AIDecisionMaker.gd:7205, :7244) and in AIPlayer (AIPlayer.gd:1678), but scoring uses ADVANCE_EXPECTED_EXTRA_INCHES = 3.5 (:2256). The post-roll recompute keeps the pre-roll heading (AIPlayer.gd:1697-1716).
- The Behind Enemy Lines push uses hard-coded Search-and-Destroy deployment-zone centres (AIDecisionMaker.gd:10393-10397, :23236) instead of the mission's deployment map.
- Mission actions are chosen only in the Shooting phase (_evaluate_secondary_actions AIDecisionMaker.gd:23784; PERFORM_SECONDARY_ACTION :16474); the Movement phase never stages a carrier. In the engine only Sabotage, Vanguard Operation and Extract Intelligence are real per-unit actions (MissionManager.gd:1966-2010); Triangulate, Booby Trap and Sensor Sweep auto-resolve (MissionManager.gd:1872-1950). So MIS-01..06 staging matters only for the first three. There is no per-unit kill attribution for Consecrate (MissionManager.gd:1976-1978), which limits MIS-26.
- Loaded transports have their shooting zeroed in movement scoring (AIDecisionMaker.gd:7398-7404), so no path drives a Firing Deck transport for its borrowed weapons (TRN-16). Post-shooting reactive moves such as SWIFT AS THE EAGLE and GO GET 'EM! are always declined because the engine has no executor for the move yet (AIDecisionMaker.gd:16397-16416), which blocks part of ADJ-24 and OBJ-43.
- Queries the AI cannot ask yet: which enemy units could Fire Overwatch on point P (line of sight, 24″, unengaged, not battle-shocked, not TITANIC, opponent has CP); the chance this transport or vehicle dies before our next turn; a registry of enemy 'ends a move within X″' triggers and debuff radii (DEN-10); enemy Heroic Intervention eligibility (unengaged, within 12″, CP); kills this turn and the opponent's last-turn kills (tracked at MissionManager.gd:3270, never read by the AI); escape lanes from P (SUR-N02).
- Deliberately kept separate (precursor vs execution, or a different move type for the same purpose): TRN-27/ADJ-26, OBJ-43/ADJ-33, DEN-25/ADJ-03, ADJ-36/COO-45, TRN-26/ADJ-37, TRN-25/DEN-01, ADJ-07/DEN-01, OBJ-34/COO-18, MIS-19/OBJ-14, DEN-28/MIS-24.
- Web sources (WebSearch snippets only; WebFetch is blocked, so no page was read in full): [1d6chan 11e Tactics/World Eaters](https://1d6chan.miraheze.org/wiki/Warhammer_40,000/11th_Edition_Tactics/World_Eaters), [Tabletop Battles: Priority Assets review](https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-priority-assets/), [Tabletop Battles: Purge the Foe review](https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-purge-the-foe/), [Warhammer Community #New40k terrain preview](https://www.warhammer-community.com/en-gb/articles/xlppkx5s/new40k-take-cover-with-updated-terrain-rules/).

## Appendix D — Research streams

| Stream | Raw candidates | Blocked / missing |
|---|---|---|
| missions | 69 | WebFetch is blocked in this session, so web evidence is search-result summaries only. Every card number and condition comes from the local official 40kdc dataset (missionCards.json), not from the web.; The raw YouTube transcript corpus is not present. Only the distilled ai_learnings.json was usable, and its own gaps note says 'Secondary mission selection and discard is barely reasoned about on cam |
| core-rules | 111 | The '11e' sources listed in the brief are 10e-era: all 13 /home/user/warhammer-40k-godot/.llm/audit_2026_launch/03_core_rules/*.md files are audit prompts framed against wahapedia wh40k10ed, every findings/03_*.md file is a 10e audit (zero mentions of 11e), and /home/user/warhammer-40k-godot/.llm/rules-audit.md is a 10e audit dated 2026-05-04. Only 03_04_movement.md was read in full. The authorita |
| youtube | 64 | research/youtube/transcripts_text.jsonl.gz is ABSENT. It is gitignored per research/youtube/README.md, and `find /` found no copy. No new quotes could be mined, verify_evidence.py cannot run, and every quote above is copied verbatim from ai_learnings.json as already verified by the original pipeline. The miner searched the themes STICKY, SECURE-then-leave, HOLD-vs-PUSH, PATIENCE, TURN-TO-COMMIT an |
| web | 80 | WebFetch was not used (blocked by the task constraint). All web evidence comes from about 64 WebSearch calls (mostly 'extended' mode) and their result snippets and summaries. No full article text was read, so quotes are snippet-level, and in a few places the exact page of a quote within a series could not be pinned (noted per candidate).; Search summaries sometimes mixed editions or were simply wr |
| factions | 57 | Every 'AI today' statement comes from reading the code and grepping it (counts and line numbers). I did not launch the game or run any AI path, as the read-only constraints required. In particular, the claim that the AI misses 11e fall-back-and-charge/shoot grants (AIAbilityAnalyzer tests for 'fall back' with a space; 11e text says 'fall-back'; detachment predicates live in EffectPrimitives) has N |
| first-principles | 108 | WebFetch is blocked, so all web evidence is WebSearch result snippets only; no article bodies were read. Several snippets came from mixed result sets where the exact originating URL is uncertain.; The raw YouTube transcript corpus (transcripts_text.jsonl.gz) is absent. YouTube evidence is limited to the verbatim quotes already in research/youtube/ai_learnings.json, with no new timestamps mined.; S |
| coverage | 59 behaviours | — |

## Appendix E — Web sources cited

- <https://1d6chan.miraheze.org/wiki/Warhammer_40> (15)
- <https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-reconnaissance/> (9)
- <https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-the-charge-and-fight-phases/> (7)
- <https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-moving-and-the-movement-phase/> (6)
- <https://odyssey40k.com/rapid-ingress-is-the-best-stratagem-in-11th-edition/> (6)
- <https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-purge-the-foe/> (6)
- <https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-priority-assets/> (6)
- <https://grimslate.com/blog/core-stratagems-guide-11th-edition> (6)
- <https://frontlinegaming.org/2026/05/28/11th-ed-40k-rules-roundup-from-the-warhammertv-battle-report/> (5)
- <https://www.warhammer-community.com/en-gb/articles/xlppkx5s/new40k-take-cover-with-updated-terrain-rules/> (4)
- <https://spikeybits.com/warhammer-40k-11th-edition-stratagems-overhauled/> (4)
- <https://grimslate.com/blog/reserves-and-deep-strike-11th-edition> (4)
- <https://grimhammertactics.com/40k-tactics-mastering-movement-in-warhammer-40k/> (3)
- <https://www.newrecruit.eu/wiki/wh40k-11e/warhammer-40> (3)
- <https://www.belloflostsouls.net/2026/04/warhammer-40k-terrain-objectives-how-they-work-in-11th-edition.html> (3)
- <https://warhammerguild.com/guides/40k-11th-edition-missions-explained/> (3)
- <https://www.wargamer.com/warhammer-40k/stratagems> (3)
- <https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-transports> (3)
- <https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-faq-compendium> (3)
- <https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-hidden-and-gone-to-ground-guide> (2)
- <https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-more-visibility-and-cover-examples> (2)
- <https://www.belloflostsouls.net/2026/06/warhammer-40k-top-5-11th-edition-rules-changes-for-competitive-play.html> (2)
- <https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-terrain-and-objectives/> (2)
- <https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-special-unit-types/> (2)
- <https://www.belloflostsouls.net/2026/04/warhammer-40k-new-close-combat-rules-revealed-melee-movement-made-easy.html> (2)
- <https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-take-and-hold/> (2)
- <https://www.tabletopbattles.com/40k-competitive-innovations-in-11th-to-take-perchance-to-hold-pt-1> (2)
- <https://www.tabletopbattles.com/40k-an-introduction-to-missions-in-11th-edition/> (2)
- <https://www.tabletopbattles.com/40k-11th-edition-force-disposition-review-disruption/> (2)
- <https://wahapedia.ru/wh40k11ed/the-rules/mission-deck-2026-27/> (2)
- <https://wellspokenman.wordpress.com/2016/10/28/deployment-interlocking-fields-of-fire-and-avenues-of-approach/> (2)
- <https://www.belloflostsouls.net/2010/08/40k-tactics-maximizing-your-assault.html> (2)
- <https://www.tabletopbattles.com/11-on-11th-recapping-the-new-warhammer-40k-rules-reveals-through-5-1/> (2)
- <https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-movement> (2)
- <https://www.greenstuffworld.com/en/blog/all-about-warhammer-40k-11th-edition-rules-news-and-armageddon-box-n144> (2)
- <https://x.com/NagayamaHammer/status/2065649251074334923> (1)
- <https://www.tabletopbattles.com/40k-start-competing-gw-terrain-layout-1/> (1)
- <https://www.wargamer.com/warhammer-40k/terrain-rules> (1)
- <https://40-carrot.app/guides/threat-range-40k> (1)
- <https://www.tabletopbattles.com/40k-start-competing-gw-terrain-layout-2/> (1)
- <https://www.tabletopbattles.com/start-competing-40k-deployment-tactics-surviving-turn-zero/> (1)
- <https://warhammerguild.com/guides/40k-11th-edition-cheat-sheet/> (1)
- <https://www.tabletopbattles.com/40k-competitive-innovations-in-11th-assault-phase-pt-2> (1)
- <https://www.40k.app/rules/10-shooting-phase> (1)
- <https://www.warhammer-community.com/en-gb/articles/wrrt241d/warhammer-40000-tactica-the-movement-phase/> (1)
- <https://www.tabletopbattles.com/ruleshammer-40k-11th-shooting-range-line-of-sight-and-visibility> (1)
- <https://thrifthammer.com/blog/warhammer-40k-11th-edition-core-keywords-cheat-sheet/> (1)
- <https://spruesandbrews.com/2026/06/01/warhammer-40000-11th-edition-core-rules-deep-dive/> (1)
- <https://www.tabletopbattles.com/11th-edition-40k-rules-deep-dive-attacks-and-the-shooting-phase/> (1)
- <https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-charge-phase> (1)
- <https://www.tabletopbattles.com/what-we-know-about-11th-edition-40k-so-far-recapping-the-new-rules-reveals-through-may-15th> (1)
- <https://www.belloflostsouls.net/2026/04/warhammer-40k-11th-edition-terrain-rules-revealed-redefining-terrain-on-the-tabletop.html> (1)
- <https://www.prismnews.com/hobbies/warhammer-40k/take-and-hold-rewards-tough-armies-in-11th-edition-40k> (1)
- <https://zatu.com/en-us/blogs/news/the-road-to-11th-edition-terrain-and-objectives> (1)
- <https://spikeybits.com/11th-edition-40k-terrain-rules-rumors-guide/> (1)
- <https://grimslate.com/blog/primary-mission-archetypes-11th-edition:> (1)
- <https://www.goonhammer.com/start-competing-how-to-screen-everything> (1)
- <https://www.tabletopbattles.com/40k-start-competing-gw-terrain-layout-7/> (1)
- <https://www.thegametown.com/blogs/news/raptors-chapter-guide> (1)
- <https://www.heresy-online.net/threads/40k-how-tos-deployment.129042/> (1)
- <https://www.tabletopbattles.com/40k-11th-edition-faction-pack-review-tyranids> (1)
- <https://bolterandchainsword.com/topic/382435-sticky-objectives/> (1)
- <https://frontlinegaming.org/2020/05/08/93739/> (1)
- <https://artificialanaleptic.github.io/WH40K11thEd.FieldManual/> (1)
- <https://wertstammer40k.wordpress.com/2016/11/11/hammer-and-anvil/> (1)
- <https://www.40k.app/rules/21-flying-and-surging> (1)
- <https://www.warhammer-community.com/en-gb/articles/4a8o9tzw/adeptus-custodes-top-detachment-tips/> (1)
- <https://www.40k.app/rules/20-strategic-reserves> (1)
- <https://www.tabletopbattles.com/detachment-focus-lions-of-the-emperor> (1)
- <https://rapidingress.com/what-is-rapid-ingress> (1)
- <https://www.wargamer.com/warhammer-40k/abilities> (1)
- <https://wahapedia.ru/wh40k11ed/factions/space-marines/Scout-Squad> (1)
- <https://www.tabletopbattles.com/40k-11th-edition-faction-pack-review-black-templars> (1)
- <https://www.tabletopbattles.com/what-we-know-about-11th-edition-40k-so-far-recapping-the-new-rules-reveals-through-may-29th> (1)
- <https://www.belloflostsouls.net/2025/11/warhammer-40k-3-movement-issues-gw-needs-to-fix-in-11th-edition.html> (1)
- <https://www.youtube.com/shorts/5DwnE4bZBBc> (1)
- <https://www.tiktok.com/@first.turn.tactic/video/7649715891055136020> (1)
- <https://www.tabletopbattles.com/40k-ruleshammer-11th-edition-fight-phase> (1)
- <https://spikeybits.com/40k-chapter-approved-tournament-companion-guide/> (1)

