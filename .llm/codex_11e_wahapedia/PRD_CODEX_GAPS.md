# PRD — Codex 11e gaps (Space Marines, Space Wolves, Custodes, Orks, engine)

Status: open · Written 2026-10-25 against `main` @ `e399052` (PR #927 merged)
Owner: unassigned · Source of every item: §8 "Evidence index"

## 1. Problem

The 11e codex work for Custodes, Orks, Space Wolves and generic Space Marines shipped
with known gaps. Some rules do nothing in online games. Some are silently wrong in
every game mode (BUG-11). Some have no player controls, are approximated, or are
missing. A few are test or doc debt. These gaps are scattered across plan files,
rulings, audits and CI allow-lists. This PRD collects them in one place, ranks them
by player impact, and turns each into a task with a clear definition of done.

## 2. Goals / non-goals

**Goals**
- Every codex rule that works in hot-seat / vs-AI also works in an online (host + client) game.
- No rule computes a wrong result in any mode (damage, AP, charge legality).
- Every rule a human is entitled to use has a player control (no "AI-only" / "headless-only" rules).
- CI allow-lists shrink: each fixed bug is removed from `tests/ci/*_known_failures.txt`.

**Non-goals**
- New factions or new codexes.
- Legends datasheets (they stay unimplemented unless an army file starts fielding them — see T-41).
- Re-balancing AI strategy beyond what a task needs to use a new control.

## 3. Priority model

Rank = **who is affected × how often × how wrong**.

| Tier | Meaning |
|---|---|
| **P0** | A core game mode loses many rules, or results are wrong in every game. |
| **P1** | A whole category of rules has no player control, or a common unit is wrong. |
| **P2** | One rule is missing or approximated, or a display is wrong. |
| **P3** | Test, doc, data or tooling debt. Players are not affected directly. |

## 4. Validation rules (apply to every task)

These come from `CLAUDE.md` and are not optional:

1. **Player-facing change ⇒ windowed scenario.** Add or update one under
   `40k/tests/scenarios/` that drives the real UI (`simulate_click`, `dispatch_action`).
   Run it with `bash 40k/tests/run_scenarios.sh tests/scenarios/<id>.json`. It must PASS.
2. **Online change ⇒ multi-peer test.** Add a `40k/tests/integration/test_multiplayer_*.gd`.
   Run it with `bash 40k/tests/run_multiplayer_tests.sh`. It must assert host and client
   state agree (phase, CP, unit flags) after the flow. Poll for sync with a bounded wait;
   never use a fixed sleep (see `test_multiplayer_dice_log_sync.gd`, commit `1b5b2c5`).
3. **Engine / math change ⇒ headless test.** Add or extend a `tests/test_*.gd`, then run
   the full gate: `bash 40k/tests/run_pretrigger_tests.sh --all`. Nothing new may fail.
4. **Known-failure hygiene.** A fix that makes an allow-listed test pass must remove it from
   `tests/ci/direct_known_failures.txt` / `gut_known_failures.txt` in the same PR.
   Otherwise CI reports it as an unexpected pass.
5. **Live evidence.** Visible changes need an in-game screenshot via the MCP bridge
   (`capture_screenshot`) in the PR. Run `verify_delivery` with `verdict: PASS` and
   confirm the debug log shows no `ERROR` lines.
6. **Version entry.** Player-facing changes prepend an entry to `40k/data/version_history.json`.
7. **Edition.** 11e only. Do not restore or keep 10e behaviour; delete 10e-only code
   and tests you touch.

---

## 5. Tasks

### P0 — Online parity

#### T-01 · Start-of-phase ability cards in online games  ·  P0 · L
**Problem.** Every "at the start of the phase" ability card returns no offers when
`NetworkManager.is_networked()`. Online players never see about 40 abilities:
- Custodes: 11 cards.
- Space Wolves: Slayer's Oath, Headhunters, Healing Balms, High King of Fenris, Njal's
  powers, Haywire Mine.
- SM detachments: Auspex Triangulation Shrines, Damocles-class Uplink, Narthecis Gauntlet,
  Tactical Insight sync.
- SM datasheets: Teleport Homer, Strategic Acumen, Spiritual Leader, Rampart, Librarian /
  Tigurius powers, Signum Array, Narthecium, Master of Shadows, Seeker of the Unfound,
  Forgefather, Overlapping Destruction, Master Tactician, Forward Assault Warsuit,
  Author of the Codex, Thunderous Force, Soul Sight, Omni-scramblers, Might of Heroes.

**Evidence.**
- Gates:
  - `SMAbilitiesA.gd:1528`, `SMAbilitiesB.gd:1332`, `SMAbilitiesC.gd:1217`
  - `SMDetachmentsA.gd:701`, `SMDetachmentsB.gd:636`
  - `SWAbilities11e.gd:1317`, `CustodesAbilities.gd` (~line 890)
- Ruling: `RULINGS.md` line 91 (WP-C7, citing WP-C5).

**Key finding.** The ruling's premise looks out of date.
`NetworkManager.broadcast_phase_enter_sync` (`NetworkManager.gd:943`) already stamps a
window opened on phase entry onto `PHASE_ENTER_SYNC` (`stratagem_window_opened`), and the
client mirrors it (`BasePhase.mirror_stratagem_window`). `BasePhase.enter_phase` already
queues phase_start entries into `_ev_deferred` before `_on_phase_enter`.

**Implement.**
1. Prove the path first. Remove the gate in ONE module (Custodes). Run a host + client game
   to a Command phase with a card offer. Confirm with logs that the host opens
   `phase_start` and the client mirrors it.
   - If the deferred queue opens after `broadcast_phase_enter_sync` has already fired, make
     the host broadcast once the queue's first window is open: call it from the deferred
     opener, or re-send `PHASE_ENTER_SYNC` when a deferred window opens on entry.
2. Remove the gate from all seven modules, and from the Custodes enhancement window
   `_cus11e_open_phase_start_window` if it is gated too.
3. Decisions go through the normal action pipeline:
   - Use-ability and decline must be host-validated.
   - When the decider is the non-active player, `allows_cross_turn_action` must let it
     through (it already keys on `get_pending_stratagem_window_decider`).
4. Waiting UX: the non-deciding peer sees the existing "opponent is deciding" overlay.
5. Update the WP-C7 / WP-S4 / WP-M4* rulings so they no longer say "not in networked games".
6. Fearsome Assault (`SMAbilitiesC.gd:974`) stays host-resolved. Verify that its
   battle-shock results reach the client through manager sync.

**Validate.**
- New `test_multiplayer_phase_start_cards.gd`. For a Custodes army, a Space Wolves army and
  a generic SM army it must check:
  - The card is offered on the right peer.
  - Using it spends nothing it shouldn't, and the effect flag is set identically on host
    and client.
  - Declining resumes the phase on both peers.
  - A card owned by the non-active player is decided by that player's peer.
- Re-run every `cus11e_ab_*`, `sw11e_ab_*`, `sm11e_ab_*` and `sm11e_det_*` windowed
  scenario. All PASS (hot-seat must not regress).
- Two screenshots: client window showing the offer, host showing the waiting overlay.

#### T-02 · End-of-phase stratagem window (SUPERHUMAN FOCUS) online  ·  P0 · M
**Problem.** `PhaseManager` skips the `phase_end` window when networked
(`PhaseManager.gd` ~line 441), so Custodes SUPERHUMAN FOCUS can't be used online.

**Implement.**
1. On the host, hold the phase completion exactly as in hot-seat.
2. Broadcast the opened window the same way as T-01. Either reuse `PHASE_ENTER_SYNC`, or
   add a `PHASE_END_HOLD` result carrying `stratagem_window_opened`.
3. The client must not advance its own phase until the host's resume arrives. Check
   `PhaseManager.gd:417` (client-side guard).
4. Do this after T-01 so both use one mechanism.

**Validate.** Multi-peer test: a Custodes player at end of Shooting is offered SUPERHUMAN
FOCUS.
- Use: CP is deducted and the effect is applied on both peers. Decline: both peers advance
  to Charge.
- The phase transition happens exactly once on each peer; assert there is no double
  `phase_completed` in the logs.

#### T-03 · Online audit of all other codex windows  ·  P0 · M
**Problem.** No test has run an online game with the new armies. Stratagems and event
windows *should* work through the action-result path, but this is unproven.

**Implement.**
1. Add a multi-peer smoke test per army (Custodes, Orks, Space Wolves, generic SM). It
   plays 1 battle round with scripted actions that trigger:
   - one Command-phase stratagem;
   - Combat Doctrines selection (SM / SW);
   - one shooting reactive stratagem used by the non-active player;
   - one fight-phase stratagem.
2. Fix any desync found. Log each fix in RULINGS / changelog.

**Validate.**
- Each smoke test asserts state-hash equality after every action. The existing
  `_state_hash` mechanism serves for this.
- Runs in CI's "Multi-peer integration (GUT)" job and stays green.

#### T-04 · Investigate 2× slower load-sync on the multi-peer job  ·  P0 · S
**Problem.**
- On the PR #927 branch, host→client "loaded state" RPC latency was ~1.7 s, against
  ~0.8 s on `main`.
- Once the client didn't receive it within 3.4 s, so `test_dice_log_sync` failed until it
  switched to polling.

**Implement.** Profile the host's phase entry after `load_save` with the codex modules
loaded. Suspects:
- the `phase_start_entries` scans (they iterate all units for every module, every phase);
- the `load()` calls per hook in `BasePhase.enter_phase` and `PhaseManager`.

Cache the scripts as `preload` constants. Return early when no unit of that faction is
present.

**Validate.**
- Measure `SYNCING LOADED STATE` → `CLIENT RECEIVED LOADED STATE RPC` in the multi-peer
  log on `main` and on the fix branch. It must be no more than 1.2× `main`'s.
- Include the numbers in the PR.

---

### P0 — Wrong results in every mode (BUG-11 family)

#### T-10 · 11e melee drops attacker +Damage modifiers  ·  P0 · M
**Problem.** The 11e branch of melee allocation ignores +Damage from enhancements and
abilities (e.g. Hall of Armouries). The allocation code is
`RulesEngine._resolve_melee_assignment`, `RulesEngine.gd:13737`, plus its
`_hits` / `_wounds` / `_saves` helpers. Every melee attack with a +D source deals too
little damage, in all modes.

**Evidence.** `tests/ci/direct_known_failures.txt:42`
(`test_374_enhancement_resolution_398.gd`).

**Implement.**
1. Trace where the 10e / shooting path applies the damage modifier: the ModifierLedger and
   the attack-modifier aggregator.
2. Apply the same aggregator result in the 11e melee damage step. Do it once per failed
   save, and respect damage caps and Feel No Pain order.
3. Grep every "+1 Damage" / "add 1 to the Damage" ability across Custodes, Orks, SM and
   SW. Add each to a table test.

**Validate.**
- `test_374_enhancement_resolution_398.gd` passes. Remove it from the allow-list.
- A new table test (`test_melee_damage_modifiers_11e.gd`), one row per +D source in the
  four codexes, checks that the damage per unsaved wound equals the printed value.
  Use a fixed seed.
- Windowed scenario: Custodes Hall of Armouries in melee. The resolution dock shows the
  modified D and the game log shows the correct wounds lost. Screenshot.

#### T-11 · 11e charge "within 1"" obligation not enforced  ·  P0 · M
**Problem.**
- Rule 11.04 requires charging models that can end within 1" (base contact rules) to
  do so.
- `RulesEngine.validate_base_to_base_possible_rules` uses the 2" engagement range
  instead.
- Illegal charge moves are therefore accepted in every mode.

**Evidence.** `direct_known_failures.txt:44` (`test_b2b_rules_standalone_check.gd`), and
`gut_known_failures.txt:63-64` (`test_barricade_engagement_range` and
`test_base_contact_enforcement::test_model_could_reach_within_1in_but_didnt`).

**Implement.**
1. Read the 11e core rules text (wahapedia 11e core rules, charge move). Encode the exact
   distance: 1" for the "must end within" obligation, distinct from the 2" engagement range.
2. Update the validator and the charge-move UI feedback (the red / illegal-move reason).

**Validate.**
- The three allow-listed tests pass and are removed from both lists.
- Windowed scenario: a charge that leaves a model 1.5" away when it could reach 0.9" is
  rejected, and the reason text is shown. Screenshot.
- AI-vs-AI: 3 games complete with no charge-move errors in the log.

#### T-12 · Positive-AP legacy fixture profiles  ·  P3 · S
**Problem.** The legacy `WEAPON_PROFILES` test fixtures store AP as a positive number, and
the 11e allocation path adds it to the save. Only the
`test_custodes_lions_silent_hunters` fixture is affected; real army data is signed.

**Implement.**
1. Make every fixture AP signed.
2. Add an assertion in the profile loader: AP must be ≤ 0 at 11e. Log a warning and
   negate it otherwise.

**Validate.**
- `test_custodes_lions_silent_hunters.gd` passes and is removed from the allow-list.
- Full gate: nothing new fails.

---

### P1 — Rules with no player control

#### T-20 · Redeployment-step UI  ·  P1 · L
**Problem.**
- `RedeploymentPhase` lists the units that may redeploy, but a human can't move them.
- The AI skips the step.

**Affected rules:**
- Custodes: Castellan's Mark.
- Orks: Kaptin's Hat, Razgit's Magik Map.
- SM: Cyber-familiar, Strategium Command.
- SW: Hunter's Guile, Chariots of the Storm.

**Implement.**
1. Redeployment panel:
   - List each eligible unit with its source rule and remaining slots (e.g. "Strategium
     Command 2/3").
   - Per unit, offer "Redeploy" (pick up the unit and place it in the owner's deployment
     zone, with deployment legality rules) or "Move to Strategic Reserves" where the rule
     allows it.
   - Add a "Done" button.
2. Actions:
   - `REDEPLOY_UNIT {unit_id, positions}` and `REDEPLOY_TO_RESERVES {unit_id}`, both
     host-validated against the redeploy table.
   - `END_REDEPLOYMENT`.
   - Add them to the network exempt list if the deciding player can be the non-active one.
3. AI: use the slots with a simple heuristic: move into reserves units that would be
   exposed turn 1, otherwise skip. Log the decision.
4. Alternation: follow the core rules order. The player who goes first redeploys first, or
   use the order from the rules text, whichever applies.

**Validate.**
- One windowed scenario per rule family (Castellan's Mark, Kaptin's Hat, Cyber-familiar,
  Hunter's Guile): redeploy one unit, send one to reserves, slots decrement, Done advances.
  Screenshots.
- A multi-peer test for the redeploy flow.
- Headless: an illegal position (outside the zone, overlapping) is rejected.

#### T-21 · Interactive moves for NO ESCAPE, RAPID REACTIONS, SELFLESS SERVICE  ·  P1 · M
**Problem.** These Custodes stratagems auto-resolve their moves. The player can't choose
where the models go.

**Implement.** Reuse the existing reactive-move follow-up (the SCARPER! / normal-move
follow-up via `allows_cross_turn_action`). Open the movement controller limited to the
printed distance and restrictions, with a confirm button.

**Validate.**
- One windowed scenario each: the move is placed by clicks, distance is enforced,
  confirming resumes the window.
- A multi-peer test for one of them, decided by the non-active player.

#### T-22 · Swift Ruin / 11e RAPID INGRESS human offer  ·  P1 · M
**Problem.** 11e RAPID INGRESS has no human offer, so Venatari Swift Ruin can only be
triggered by the AI or by tests.

**Implement.**
1. Add the RAPID INGRESS window at the end of the opponent's Movement phase for units in
   reserves, with the printed CP cost.
2. Swift Ruin shows as a variant: −1 CP, and it's exempt from once-per-phase.

**Validate.**
- Windowed scenario: a human uses RAPID INGRESS, then Swift Ruin in the same phase. CP is
  correct and both units are set up.
- Headless: the once-per-phase rules hold.

---

### P1 — Engine-wide unit correctness

#### T-30 · Duplicate weapons on one model fire once  ·  P1 · L
**Problem.** A model can't carry two copies of the same weapon, so the second copy never
attacks. Affected: Land Raider, Thunderhawk, Telemon (2× Twin Neutronium Cascade
Projectors), Stompa (5× Big Shootas), and others.

**Implement.**
1. Represent weapon count per model in the resolved loadout (e.g. `{weapon_id, count}`, or
   repeated ids that the attack builder keeps).
2. Make the attack builder generate `count ×` attacks.
3. Audit converters and save migration so old saves keep working.

**Validate.**
- A headless test asserting total attacks for Land Raider, Thunderhawk, Telemon and Stompa
  equals the printed weapons × A.
- Windowed scenario: the shooting panel lists both copies (or ×2), and the dice tray shows
  the doubled dice. Screenshot.
- Full gate, plus AI-vs-AI for Orks and SM (no errors).

#### T-31 · Per-model characteristics (`stats_override`)  ·  P1 · M
**Problem.**
- The converters never emit `meta.model_profiles` `stats_override`.
- Mixed units therefore use the unit's M, T and Sv for every model.
- Affected:
  - Space Wolves: Hunting Wolves in Wolf Scouts and in Wolf Guard Headtakers.
  - Orks: Gretchin with Runtherd, Kroot Hounds.
  - Sisters: Repentia Superior.

**Implement.**
1. Emit `stats_override` from the datasheet import for models with their own profile row.
2. Have movement, wound and save lookups read the per-model value.

**Validate.**
- A headless test: a Hunting Wolf in Wolf Scouts moves with its own M and saves with its
  own Sv, while a Scout model uses its own.
- A windowed scenario showing per-model stats in the datasheet panel.

#### T-32 · Per-model loadout data errors  ·  P2 · S
**Problem.**
- Wolf Guard Headtakers resolve weapons on the wrong models.
- Wolf Guard Terminators B resolve 8 Storm Bolters for a roster with 4.
- The Victrix Honour Guard per-model loadout isn't modelled.

**Implement.** Fix the data / overlay so the loadout resolver matches the printed
composition.

**Validate.** Extend `test_loadout_resolution` with these units, and check exact per-model
weapon lists.

---

### P2 — Single-rule gaps and approximations

#### T-40 · Advanced Firepower (Caladius Annihilator)  ·  P2 · M
**Implement.** Against MONSTER / VEHICLE ranged targets, re-roll one Hit roll, one Wound
roll and one Damage roll. Reuse the single-die re-roll plumbing from WP-C46 (Magna
Imperator).

**Validate.** A headless test with a fixed seed showing exactly one re-roll per step. A
windowed scenario showing the re-roll in the dice tray / log.

#### T-41 · Legends datasheets (Custodes)  ·  P3 · M
Decide first. If any army file or the builder exposes them, implement:
- Venerable Contemptor (Unyielding Ancient)
- Venerable Land Raider (Assault Ramp)
- Aleya
- Valerian
- the Adrasite, Sagittarum and Pyrithite Sodalities

Otherwise document them as permanently out of scope.

**Validate.** Either a scenario per implemented ability, or a builder test that Legends
units can't be added.

#### T-42 · Assault Vehicle (Coronus Grav-Carrier, Anathema Psykana Rhino)  ·  P2 · S
**Blocked:** the local 11e core rules define no shock-disembark move. Re-check the current
wahapedia 11e core rules. If the move exists, implement it as a disembark-after-advance
follow-up. If not, mark it N/A in the audit.

**Validate.** A scenario, or an audit row updated with the rules citation.

#### T-43 · WOLF TOTEMS timing  ·  P2 · S
**Problem.** It's used before the mortal wounds are allocated (from the shooting panel),
not at the moment they're inflicted.

**Implement.** Open a window when mortal wounds are about to be inflicted on the eligible
unit.

**Validate.** A windowed scenario where the window appears at the right step; the damage
is reduced as printed.

#### T-44 · Telepathic Assault ignores psychic-only Feel No Pain  ·  P2 · S
**Validate.** A headless test where a psychic-only FNP target rolls FNP against Telepathic
Assault mortal wounds.

#### T-45 · Bodyguard engagement ignores the attached leader  ·  P2 · S
**Implement.** Use the Attached-unit engagement (any component) for the bodyguard check.

**Validate.** A headless test, plus a scenario with an attached unit engaged only through
its leader.

#### T-46 · Teleport Homer token not drawn  ·  P2 · S
**Implement.** Draw a token visual at the placed position, and remove it when it's used or
the unit dies.

**Validate.** A windowed scenario with a screenshot of the token on the objective.

#### T-47 · Laurels of Vigilance card shows the undiscounted cost  ·  P2 · S
**Validate.** A scenario asserting the card label matches the CP actually deducted.

#### T-48 · Creeping Dread log line shows the unmodified total  ·  P2 · S
**Validate.** A scenario / log assertion: the logged total equals the modified roll used.

#### T-49 · Imperium's Sword weapon profile  ·  P2 · S
The source prints no profile. Check the latest wahapedia / FAQ. Add the profile if it's
published, otherwise keep it flagged in the import report.

#### T-50 · Approximated rulings to revisit  ·  P2 · S each
- **Priority Target Identified** offers every terrain piece, because line of sight to
  terrain isn't modelled. Implement LoS to the terrain footprint using `TerrainManager`
  sight points.
- **Teleport Homer** is offered at every phase start of round 1 until it's placed. Confirm
  against the rules text. Restrict it to the printed timing if the text is stricter.

**Validate.** A headless test per ruling, then update `RULINGS.md`.

#### T-51 · Ork abilities not implemented  ·  P2 · M
Deff from the Shadows, Pilin' Out, Pulse Jet, Big'ed Bossbunka's three abilities, the
Runnin' wiv da Herd keyword swap, Get Out da Way!
(`PLAN.md` "Known follow-ups", `ork_abilities_audit.md`).

**Validate.** One `ork11e_ab_*` scenario per ability, and update the audit rows.

---

### P3 — Builder, data, tests, docs

| ID | Item | Implement | Validate |
|---|---|---|---|
| T-60 | Browser builder doesn't flag Sons of Russ / other-Chapter units | Validation rule in the builder (`server/public/js`) | `npm test` builder test |
| T-61 | `canon.mjs` hand-edited; the generator's output already differs from `main` | Run `scripts/40kdc/bundle-browser.mjs`, review and commit the diff. Add a CI check that the generated files are up to date | CI step fails on drift |
| T-62 | 2 failing `codex-builder-parity.test.mjs` cases (Orks Fortification overlay vs 40kdc) | Check whether they also fail on `main`, then fix the overlay or the expectation | `npm test` green |
| T-63 | 10e Combat Doctrines code path still in `CommandPhase` | Delete the 10e branch and its 10e-only tests, per the "no 10e" rule | Full gate and doctrine scenarios PASS |
| T-64 | Design doc uses "Oath of Moment" as an example | Change the example in `docs/design_guidelines_2d_topdown.md` **in a PR that also fixes T-65**. Changing that doc pulls the T## scenarios into CI | — |
| T-65 | T23 / T27 / T39 visual scenarios fail on `main` (no `EndPhaseButton`; DatasheetModal scroll step 33) | Implement the End Phase button per guideline T23 / T27 (fixed bottom-right offset 200, 60) and fix the datasheet scroll container — or, if the guideline is obsolete, retire the scenarios with a recorded decision | `run_scenarios.sh tests/scenarios/visual/T23*.json T27* T39*` PASS |
| T-66 | Custodes / Orks tutorial rosters and lesson fixtures are pre-codex | Rebuild `tutorial_*.json`, the lesson save fixtures and the lesson text | Tutorial scenarios PASS |
| T-67 | Save fixtures / AI-lab baselines not regenerated for codex lists | Regenerate and re-baseline | AI-lab CI green |
| T-68 | `recon_stomps.json` is 2280/2000 pts | Re-author it as a legal list, plus its AI plans | Builder validation and AI-vs-AI |
| T-69 | `sm11e_m2a` fixture Ork side scores 0 VP | Give the opposing list a realistic size | AI-vs-AI shows both sides scoring |
| T-70 | Stale counts in known-failure comments (`test_ai_ability_awareness` 72/1, `test_audit_already_done_pin` 251/6) | Update the comments, or fix the underlying failures | `check_junit` OK |
| T-71 | CI: the push-event "changed scenarios" diff uses the previous push, so reverting a file re-selects its scenarios | Diff against `merge-base(origin/main, HEAD)` for push events on PR branches, as `pull_request` does | A revert-only push selects no scenarios |

---

## 6. Suggested order

1. **T-01 → T-02 → T-03 → T-04.** Online parity shares one mechanism: build it once,
   then audit.
2. **T-10, T-11 in parallel.** These are independent engine fixes; each shrinks the
   allow-list.
3. **T-20.** Redeployment UI unlocks 8 rules across 4 factions.
4. **T-30, T-31.** Engine-wide unit correctness.
5. **T-21, T-22, then the P2 list by faction.**
6. **The P3 table, batched.** T-64 must be in the same PR as T-65.

## 7. Done criteria for the whole PRD

- No `is_networked()` early-return remains in any `phase_start_entries` or in the
  `phase_end` hold. Multi-peer smoke tests for 4 armies are green in CI.
- `direct_known_failures.txt` / `gut_known_failures.txt` contain no `BUG-11` lines.
- No audit row says "NOT CLICKABLE", "headless only" or "auto-resolved" for a rule a human
  can use.
- Every task above is either merged with its validation evidence (scenario id, test name,
  screenshot path), or marked N/A with a citation.

## 8. Evidence index

- `.llm/codex_11e_wahapedia/PLAN.md` — Custodes / Orks rows and "Known follow-ups".
- `.llm/codex_11e_wahapedia/PLAN_SPACE_MARINES.md`, `PLAN_SPACE_WOLVES.md` — "Known follow-ups".
- `.llm/codex_11e_wahapedia/RULINGS.md` — WP-C5 (phase_end), WP-C7 line 91 (phase_start),
  WP-S2..S4, WP-M2a..M4c (redeploy NOT CLICKABLE, approximations).
- `.llm/codex_11e_wahapedia/custodes_abilities_audit.md`, `ork_abilities_audit.md`,
  `space_marines_abilities_audit_[abc].md`, `space_wolves_abilities_audit.md`.
- `40k/tests/ci/direct_known_failures.txt:41-44`, `gut_known_failures.txt:63-64` — BUG-11.
- `40k/autoloads/NetworkManager.gd:943-976` (`broadcast_phase_enter_sync`),
  `PhaseManager.gd:436-446` (phase_end gate),
  `phases/BasePhase.gd:76-106, 415-452, 1267-1281` (phase_start queue, F4 mirroring).
- PR #927 CI history — multi-peer load-sync latency (T-04), push-event scenario selection (T-71).
