# Launch Audit — 2026-07-31 (publish-ready in 24h directive)

**Order:** publishable game, 11th-edition rules-complete, Steam-grade UI polish, within 24 hours.
**Method:** three parallel deep audits (multiplayer/turn-handling, 11e rules coverage, UI/shipping
readiness) + live drive of the running game via the MCP bridge + reconciliation against the
2026-05 audit (`.llm/audit_2026_launch/findings/06_SYNTHESIS.md`) and open GitHub issues.

---

## Executive summary

1. **Rules engine: ~90–95% of the 11e core rulebook is implemented and validated.** The 11e
   migration tracker (`ISSUES.md`, ISS-037…074) is 69/74 DONE with zero open *rules* issues.
   Every phase, weapon ability, core stratagem, allocation flow, terrain category, and
   mission-scoring layer exists and is tested (385 headless tests + 459 windowed scenarios).
   The 2026-05 launch-blocker list (AP-sign bug etc., issues #364–#389) is fully closed.
2. **Play-and-pass is ~90% built already — it just has no shell.** The game *is* a hotseat game
   at its core: Human/Human in the menu works end-to-end today, every phase gates input to the
   active player, reactive windows route to the correct defender. What is missing is purely the
   handoff ceremony: a "pass the device" screen, privacy for the secret Formations step, and a
   settings toggle. **This is the launch feature to bet on** (see §2). Networked MP exists (LAN +
   web relay, host-authoritative, seeded RNG) but its integration suite is red, it has no
   reconnection, and it has drifted ~9 days without exercise — ship it as "beta", not headline.
3. **The real launch blockers are in the shipping shell, not the game**: no Windows export
   preset (and the CI release workflow references presets that don't exist), the MCP
   remote-control server + test harness autoloads ship inside player builds (open TCP port
   9080 on players' machines), stock Godot icon, no display settings (forced fullscreen),
   no audio content, 5.8k `print()` calls, and the **Games Workshop IP question** (title,
   datasheet names, scraped data) which only the owner can resolve.

**Verified live this session:** end-of-game after round 5 works (GameOverDialog with final
score + VP chart) — **GitHub issue #319 can be closed**. Formations → roll-off → deployment
flow drives cleanly. Human/Human handoff moments confirmed to have no prompt (and the
Formations dialog for P2 appears while the top bar still says P1 — stale turn indicators).

---

## Step-by-step plan

### Phase A — Play-and-pass launch feature (in progress, this branch)

The multiplayer audit's key insight: **"who has the controls" ≠ `meta.active_player`** —
fight-phase alternation and ~11 reactive windows (saves, overwatch, heroic intervention,
counter-offensive, coherency removal…) put the *other* player at the keyboard without
flipping `active_player`. A naive per-flip prompt would fire 30–50×/game and still miss
those windows. So:

- **A1. HandoffManager autoload** — full-screen privacy/handoff modal ("Pass the device to
  Player 2 — Adeptus Custodes"), input-blocking, controller-friendly, shown only in local
  Human-vs-Human games (never networked, never vs-AI, never under the scenario harness
  unless a test opts in).
- **A2. Trigger tier "turn boundaries" (default):** player-turn flips (each COMMAND phase
  start), Formations secret-declaration swap (P1 confirm → P2 dialog — the docstring says
  these are secret and today they leak), and deployment-phase entry (announce who deploys
  first; per-unit deployment alternation stays promptless — open information).
- **A3. Settings toggle** (Gameplay tab): Handoff prompts on/off.
- **A4. Reactive windows:** keep the existing MA-42 blocking overlay, but name the deciding
  player ("Player 2 — your decision") instead of "opponent". (Follow-up)
- **A5. Roll-off privacy:** today P1 physically rolls both dice in hotseat
  (`Main._roll_off_local_human`). Acceptable v1; label it. (Follow-up)
- **A6. Seat names** ("Rob" / "Sam") in menu + banners. (Follow-up, cosmetic)
- **A7. Windowed scenario test** asserting the modal appears/blocks/clears at each boundary.

Estimated: A1–A3+A7 land now; A4–A6 are 1–3 days more.

### Phase B — Shipping shell (parallelizable, mostly small)

1. **Strip dev tooling from player builds** (S): remove/gate `MCPServer`, `TestModeHandler`,
   `ScenarioRunner`, `AIBenchmarkRunner` autoloads in exports (feature-tag or
   `OS.has_feature("editor")`/env gate); add exclude_filters to the macOS preset; exclude the
   9 loose `test_*.gd` at `40k/` root. The open 9080 TCP listener in a shipped build is a
   review-killer and a security flag.
2. **Windows export preset + fix `release-build.yml`** (S): presets named in CI don't exist;
   no Windows preset at all. Align Godot version (CI pins 4.4.1, project declares 4.6).
3. **Display settings + windowed mode** (M): game force-launches fullscreen with zero
   video options; add window mode/resolution/vsync tab to Settings.
4. **App icon / version / copyright** (S–M): stock Godot robot icon everywhere today.
5. **Main-menu restructure** (M): title art, one-click "Quick Battle", buttons above the
   fold (Load/Tutorial/Settings/Quit are below the fold at 1080p today), move the 14-dropdown
   config form behind "Custom Battle", remove the two permanent controller-diagnostic labels.
6. **Release logging profile** (M): `DebugLogger` hardcodes DEBUG-level + file+console;
   5,788 print() calls; gate behind `OS.is_debug_build()`.
7. **Audio** (L): zero recorded audio in the repo; Music slider controls an empty bus. Even
   2–3 licensed tracks + UI/dice SFX transforms perceived quality. (The synthesized dice
   blips are a nice touch but not enough.)
8. **Debug keys** (S): `9` = unrestricted-movement cheat, `L`/`O` debug overlays — gate to
   debug builds.
9. **Quit to Desktop** in pause menu (S).
10. **HUD top-bar overlap** (M): ~10 runtime widgets appended to one HBox overlap the
    End-Phase button at 1080p (visible in repo screenshots); needs layout discipline pass.
    Same for phase-tab strip vs pad-hint-bar collision at the bottom edge.

### Phase C — Rules completion (small, high-value)

1. **G1 — enforce "same stratagem once per phase" (11e 15.01)** for the 6 core stratagems
   declaring empty restrictions (`StratagemManager.gd:4054-4150` / `:911`). One-line-ish. ✳
2. **G2 — battle-shock result bypasses the diff pipeline** (`CommandPhase.gd:985-1010`
   mutates state directly; invisible to undo/replay/MP sync). ✳
3. **G7 — verify overwatch consumes `no_hit_rerolls`** (lead, not confirmed bug).
4. G3/G4 — mission "action" content (registered framework, one generic action; some 11e
   primary "action" rules score 0 by design) — scope call for the owner.
5. G6 — attack-sequence orchestration still triplicated in RulesEngine (ranged interactive /
   ranged fast / melee) — top source of future rules drift; refactor post-launch.

### Phase D — Content & positioning (owner decisions needed)

- **Factions:** 3 playable (Custodes incl. Lions, Orks incl. 3 detachments, Space Marines
  partial). 2 tasks remain `[STUB-PENDING-IP]`. Fine for a "2.5-faction launch" if framed.
- **GW IP:** title, unit names, scraped Wahapedia-derived data. Only the owner can decide
  (rename/reskin vs. accept risk). Blocks Steam more than anything technical.
- **Networked MP positioning:** label LAN/Online as *Beta* in the lobby UI for launch;
  fix-forward after. Its architecture is sound (host authority, action diffs, seeded RNG,
  desync hashes) but the 770-line hand-maintained client visual-replay switch and red
  integration suite make "polished" claims unsafe within 24h.

### Honest 24-hour scope

Achievable in 24h: Phase A (A1–A3, A7), Phase B items 1, 2, 8, 9, and Phase C items 1–2.
Not achievable in 24h: audio content, menu art pass, full HUD relayout, IP resolution,
Steamworks integration, 26-faction anything. Those are flagged, sequenced, and estimated
above rather than pretended.

---

## Progress log (updated 2026-08-01, same branch)

Shipped on `claude/40k-godot-audit-azjslb` since this audit was written:

- **Phase A (play-and-pass):** A1 HandoffManager privacy screen ✔, A2 turn-boundary
  triggers incl. Formations secrecy ✔, A3 settings toggle ✔, A4 reactive overlays name
  the deciding player ✔, A6 seat names ✔, A7 windowed scenario (13/13) ✔.
  A5 (roll-off: P1 rolls both dice) assessed as acceptable-by-design — both dice are
  shown side by side and rolls are random regardless of who clicks; left as is.
- **Phase B:** B1 dev tooling gated out of player builds ✔ (MCP socket opt-in,
  TestModeHandler inert in templates, macOS/all preset exclude filters),
  B2 Windows preset + CI preset-name/template fixes ✔, B3 display settings ✔
  (windowed/exclusive/fullscreen, resolution, vsync — verified live),
  B4 custom app icon ✔ (Steam capsule art still needed), B5 menu buttons above the
  fold + attribution overlap fix ✔ (controller diagnostic labels kept — explicit owner
  request 2026-07-27), B6 release logging profile ✔, B8 cheat/debug keys gated ✔,
  B9 Quit to Desktop ✔, B10 HUD top-bar overlap — verified already fixed live, no change.
- **Phase C:** C1 15.01 once-per-phase cap ✔ (+ phase-instance fix, new pin test 8/8),
  C2 battle-shock via diff pipeline ✔, G7 overwatch no-hit-rerolls verified honored ✔.
- **Extra:** shooting eligibility cache now invalidates on terrain change (real bug),
  383 scenario fixture repaired (embarked-target drift) — suite sample 11/11 green,
  online multiplayer labeled "(Beta)" in menu + lobby.

### Stale-issue triage (code evidence; recommend owner spot-check then close)

| Issue | Evidence | Verdict |
|---|---|---|
| #319 game never ends | verified live this session (GameOverDialog) | **close** |
| #45 END_FIGHT broken | `FightPhase.gd` handles END_FIGHT (3 sites) | close after spot-check |
| #37 consolidation / #34 skip pile-in | 11e global pile-in/consolidate steps implemented | close after spot-check |
| #8 mark shot models before removal | `TokenVisual.gd` marked-for-death indicator (3 sites) | close after spot-check |
| #56 per-weapon range circles | `ShootingController.gd:1911` weapon-named range circles | close after spot-check |
| #92 disembark movement types | movement disembark fully reworked (127 refs, 3 modes) | close after spot-check |
| #82 formation rotation, #41 click-model-select | no clear evidence | keep open |
| #89 multiplayer, #94 master bug list, #93 testing audit | umbrella issues | keep open |

## Multiplayer + Audio (2026-08-01, this branch)

**Online multiplayer — validated live with two ENet instances, 3 real bugs fixed:**
- Deploy over web-relay was fully broken: `_validate_model_position` is typed
  `Vector2` but the relay JSON-encodes positions to `{x,y}` dicts → validation
  crashed → blanket reject. Now coerced in place (Vector2/{x,y}/[x,y]). ENet was
  unaffected.
- Command-phase desync: `_on_phase_enter` CP generation + RNG secondary draws run
  independently on each peer, so the client saw wrong CP / an empty secondary hand
  for the whole phase. New `NetworkManager.broadcast_phase_enter_sync()` pushes the
  host's authoritative CP/VP + manager snapshot right after enter. Verified: a
  corrupted client CP is corrected on the next phase-enter, no desync fired.
- Idle peer-drop detection: ENet only times out on an unacked reliable send, so a
  peer dying while nobody acts was never noticed. Bounded the ENet peer timeout
  (4–8s) on connect. (Clean window-close sends a DISCONNECT and is instant.)
- State hashes stay identical across peers through formations/roll-off/deployment/
  first-turn. Disconnect grace dialog (Save / Continue Single-Player / Claim
  Victory) renders and recovers correctly. MP unit suite green (104 asserts).
- **Still labeled "(Beta)"**: a full 5-round game wasn't driven end-to-end, and
  "Online Play" depends on the fly.io relay server (ops story needed). Flip the
  label once those are closed. LAN host/join is solid.

**Audio — shipped (was completely silent):**
- Original generated audio (`tools/generate_audio.py`, pure stdlib — no third-party
  samples, nothing to license): ambient menu bed, tenser battle bed w/ heartbeat,
  4 UI cues. `MusicManager` autoload loops + crossfades them on the Music bus; UI
  cues on SFX. Menu buttons play click/hover. The Settings audio sliders now
  control real content.
- **Environment caveat**: the headless shim forces `--audio-driver Dummy`, which
  starts playback but doesn't advance position, so audible/sustained playback
  couldn't be measured here. Pipeline verified correct (streams load with data,
  buses routed, play() succeeds, volume tracks the slider) and matches the shipped
  DiceSoundManager. Needs a real-device listen before launch.

## Flags (things you should know)

- **Issue #319 is fixed in code and verified live this session** — close it.
- ~40 pre-September-2025 GitHub issues appear stale (many describe behavior that has since
  been rebuilt — e.g. #45 END_FIGHT, #43 save direction, #37 consolidation are all
  implemented now). Worth a triage sweep; recommend closing after spot-checks.
- Stale turn indicators during Formations: top HUD says "Player 1" while P2's dialog is
  open; right-panel unit list shows P1's army during P2's declaration. Handoff screen
  mitigates; the underlying refresh should still be fixed.
- `MULTIPLAYER_LOBBY_GUIDE.md` and `EXPORT_GUIDE.md` are stale vs. the current code.
- Web relay server (`server/relay-server.js`, fly.io) is a runtime dependency of "Online
  Play" — needs an owner/ops story before Steam.
- Save/load is genuinely mature (slots, autosave, backups, mid-phase restore); the one
  play-and-pass risk is phase-local state (e.g. mid-fight-activation) not being in
  GameState — same class of problem the MP docs flag. Autosaves at phase boundaries cover
  the practical case.
