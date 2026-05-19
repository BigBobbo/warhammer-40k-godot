# Design Guidelines: 2D Top-Down Tabletop-Faithful Warhammer 40,000

**Status:** Research synthesis, May 2026
**Audience:** Designers and engineers working on the 40k Godot client
**Scope:** UI/UX patterns for the tactical board, tokens, range/LOS overlays, phase
signaling, dice surfaces, and information panels. Pure visual/interaction design —
no rules changes.

## Executive summary

Three principles recur across every successful 2D top-down tactical game and every
mature VTT. They should anchor every UI decision in this repo:

1. **The board is the HUD.** Wounds, status, threat, and range belong on the
   token and the tile — not in side panels. Side panels are for *details* the
   player consults when curious, never for primary decisions.
2. **Preview before commit.** Damage forecasts, charge-range rings, and
   movement-cost colorings must render *during* target selection, sourced from
   `RulesEngine`. Frozen Synapse's Sim/Prime split is the gold standard.
3. **Layering is a budget, not a feature.** Show at most two semantic overlays
   at once. Invisible, Inc.'s most-cited flaw is overlay collision; we are
   currently building toward the same trap with simultaneously-visible
   deployment zones, movement circles, engagement rings, and threat highlights.

Everything below applies these principles to nine specific subsystems.

## Method

- **Reference set (2D only):** Into the Breach, Hoplite, Wargroove, Advance Wars
  (Re-Boot Camp), Door Kickers 1 & 2, Frozen Synapse, Invisible Inc., Battle for
  Wesnoth, Templar Battleforce, Songs of Conquest, Battle Brothers.
- **VTT set:** Foundry VTT, Owlbear Rodeo, Roll20.
- **Current-state evidence:** screenshots in
  `40k/test_results/audit_2026_05/screenshots/` and
  `40k/test_results/playthrough_*.png`, plus existing visual scripts under
  `40k/scripts/` (`MovementRangeVisual`, `EngagementRangeVisual`,
  `CoherencyCircleVisual`, `ChargeTrajectoryPreview`, `DeepStrikeExclusionVisual`,
  `DamageFeedbackVisual`, `DiceRollVisual`, `ChargeArrowVisual`, `BoardVisual`,
  `BoardBackground`).
- **Excluded:** 3D tactical games (XCOM, Battletech, Rogue Trader, Chaos Gate,
  Wartales) — they solve different camera/perspective problems and patterns
  don't transfer cleanly.

## Current-state observations (May 2026)

Sourced from the audit screenshot set, not subjective opinion.

| Subsystem | Today | Concern |
| --- | --- | --- |
| Token design | Round faction-color base with a 1–2 letter label and faint sub-label | Tokens are small relative to the board; sub-labels illegible at typical zoom |
| Faction vs. player color | Token color = faction (Custodes yellow, Witchseekers blue); deployment zone color = player slot (P1 blue 15% alpha, P2 red 15% alpha) | Two independent color axes collide. If both players run blue factions, P1/P2 identity is lost. |
| Range visualization | Pale yellow movement circle, translucent blue engagement ring | Color semantics aren't consistent — blue means "ally" in some shots and "range" in others. |
| Phase signaling | Phase name in top bar (`Movement Phase Player 1`, `Shooting Phase`, ...) + an `End [Phase]` button | Subtle. No persistent six-phase tracker, no breadcrumb of sub-states. New players can't tell what phase 4-of-6 is or what's left. |
| Side panels | Persistent left log + right unit roster + right phase-controls | Eats roughly 35–45% of horizontal screen real estate; the board is the smaller half. |
| Modals | Secondary Missions, Battle Formations, Weapon Order, Epic Challenge | Large, opaque, centered — completely cover the board during the decision they're asking about. |
| Highlight chrome | Many UI buttons ringed in bright orange ("clickable now") | Visual noise. Multiple competing highlights at once. |
| Dice/combat results | Weapon-order modal + right-panel "Result" line + game log | Split across three surfaces; nothing on the affected tokens. |
| Terrain | Darker green geometric blocks on lighter green base; "LoS Debug" toggle in top bar | Cover values (none/light/heavy) not surfaced diegetically on the tile. |
| Engine support | Strong — dedicated `*RangeVisual`, `*Preview`, `Damage*Visual`, `Charge*Visual` scripts already exist | Primitives are present. Recommendations below are mostly *visual* and *composition* changes, not new systems. |

## The nine sub-questions

### 1. Camera & perspective

**Reference findings.** Top-down 2D works at every studied scale (Hoplite single
screen → Wesnoth panning hex map → Frozen Synapse vector buildings). The
constant: a single fixed orthographic angle, no tilt, no rotation. Owlbear and
Foundry both reject perspective tilt because round bases stop reading as round
when tilted.

**Today.** Pure 2D top-down via `Camera2D` at `Vector2(880, 1200)` in `Main.tscn`.
Correct foundation.

**Recommendations.**
- Keep the camera locked to top-down. No isometric drift.
- Add a **fit-board** keybind (`F`) and a **fit-selection** keybind (`Shift+F`) —
  Owlbear and Foundry both surface this and players use it constantly.
- When a modal opens, briefly zoom-to-fit the *affected* tokens so the player
  sees what the decision is about (see §3, Modals).

**Anti-pattern.** Don't add a rotate-board feature. Wesnoth specifically chose
not to; players orient via consistent map cardinality, not view rotation.

### 2. Token & unit readability

**Reference findings.**
- Foundry's **disposition ring** (teal/yellow/red) is the proven friend/foe
  signal. Owlbear's **single outline color** does the same job with even less
  chrome. Frozen Synapse: **green=you, red=enemy, yellow=neutral** — invariant
  across every screen.
- Advance Wars: **faction = hue, type = silhouette**. Never overlap the two
  axes. Re-Boot Camp's 3D refresh muddied silhouettes (MD Tank vs. Tank) and
  was widely criticized; the lesson is silhouette differentiation > fidelity.
- Hoplite: every unit type has *one* iconic side profile. Players parse the
  board by shape, not by reading labels.
- Roll20's 9-icon status strip is universally cited as cryptic — keep status
  icons low and labeled-on-hover.

**Today.** Single-letter labels on round colored bases. No silhouette
differentiation between unit types — an Intercessor token and a Terminator
token are both "circle with letters". Faction color and player color are
conflated.

**Recommendations.**
- Adopt a **two-ring token** (Foundry pattern):
  - Inner ring color = **faction color** (Custodes gold, Ultramarines blue, …).
    Player picks at army selection.
  - Outer thin ring = **player slot** (P1 / P2). Keep slot colors fixed and
    distinct from any faction (teal for P1, magenta for P2 work; current
    blue/red collide with common faction palettes).
- Inside the ring, render a **unit-type silhouette** at high contrast — even a
  64×64px monochrome glyph (boltgun for Intercessor, hammer for Assault
  Terminator, pintle MG for tank) reads at any zoom. Letters/names live
  *under* the base, auto-hidden when zoomed out below a threshold.
- Cap **status icons at three** at fixed token-edge slots (top-left: army
  status like Battle-shocked / Below Half; top-right: phase status like Fought
  / Shot / Advanced; bottom-right: special — overwatch armed, sticky-objective).
  Overflow collapses to a `+N` chip that expands on hover.
- Multi-wound models: small **`W/Wmax` chip on the base edge**, not a thin HP
  bar. Bars at 32mm scale are illegible (Owlbear specifically removed them
  for this reason).
- Active unit (currently activating) gets a **pulsed brightened ring** —
  Foundry's turn-marker pattern, Wesnoth's grayed-when-moved inverted.

**Anti-pattern.** Don't put more than two text strings on a token. Faded
sub-labels under tokens are currently illegible — remove them.

### 3. Modals & screen real estate

**Reference findings.** Every studied game uses **non-blocking surfaces** for
in-tactical decisions. Wesnoth's attack dialog is the rare exception and is
*small, side-anchored, and dismissible*. Songs of Conquest's most-cited
complaint is its off-convention end-turn placement; Battle Brothers' Dev Blog
#75 redesign was rejected because ornament hurt readability.

**Today.** Secondary Missions, Battle Formations, Weapon Order, Epic
Challenge — all large opaque centered modals that cover the board.

**Recommendations.**
- Reclassify dialogs:
  - **Out-of-play setup** (Secondary Missions, Battle Formations,
    Warlord/Reserves): full modal is fine, but pin the unit roster to one
    side so the player sees what they're building from.
  - **In-tactical decisions** (Weapon Order, Epic Challenge, Stratagem
    confirm, Wound Allocation): convert to **side-anchored panels** that
    take the existing right-side phase-controls column. Board stays
    visible. Add a `Esc` to cancel and a one-line preview of the
    consequence ("Use Epic Challenge: pin closest enemy CHARACTER. 3 CP.").
- Auto-zoom-to-fit affected tokens when an in-tactical decision opens so
  the player can see *what* the decision is about (Door Kickers' "pause
  centers on the active operator" pattern).
- Establish a **convention**: bottom-right = End Phase, top-right = global
  meta (save, settings), left = log, right = context. Match Wesnoth + Foundry,
  avoid SoC's top-right end-turn.

**Anti-pattern.** Avoid stacked modals. If a wound-allocation decision opens
during a shooting resolution that itself opened during a normal Shooting
phase, the player should never see two modals at once — only the innermost.

### 4. Phase & turn structure

**Reference findings.** No studied game has six phases. The closest analog is
Songs of Conquest's interleaved unit-turns + wielder-spells. We are inventing
the convention for our 6-phase domain — but every studied game gives the
active player a **persistent, unambiguous, on-screen "where am I in the turn"
cue**:
- Wesnoth: faction-colored hex tinting + lit End Turn button.
- Advance Wars: full-screen banner at turn start + persistent border color.
- Battle Brothers: top initiative bar.
- Frozen Synapse: phase pill above the play area.

**Today.** Phase name in a small top-bar label. No multi-phase tracker. No
sub-state breadcrumb.

**Recommendations.**
- Add a **top-center phase bar**: six pills `Command → Movement → Shooting
  → Charge → Fight → Morale`. Active pill glows in player color; completed
  pills dim; future pills disabled. Always visible. Click on past pills is
  inert; click on future pills shows a tooltip ("Resolve Movement first").
- Beneath the active pill, render a **sub-state breadcrumb** for phases
  that have steps:
  - Shooting: `Select Unit → Select Target → Hits → Wounds → Saves →
    Damage`. Light each crumb as it becomes current.
  - Charge: `Declare → Roll → Move → Pile In`.
  - Fight: `Fights First → Select Fight → Pile In → Attacks → Consolidate`.
- **Active-player edge tint**: the outer 4px of the play area tinted in
  player color while it's their turn. Cheap, always-on, never blocks
  anything. (Mirrors Wesnoth's faction-colored side flags.)
- **End-Phase button bottom-right**, single canonical location across every
  phase. Never relocate it; never repurpose middle-click (Templar
  Battleforce's bug).

**Anti-pattern.** Don't put the phase name only in the top bar. New players
in our current screenshots cannot tell if they're in Shooting step 1 of 6
or step 5 of 6.

### 5. Movement & range visualization

**Reference findings.**
- Foundry's **Drag Ruler** + path-coloring is the single most-cited
  "feels like the real tabletop" UX pattern: as the model drags, paint the
  path green within Move, yellow within Advance, red beyond.
- Wargroove **two-layer shading**: solid color = move-into range, outline
  ring = shoot-from range. One glance, two pieces of info.
- Hoplite: movement range is *always visible* at idle for the player's
  units. No "select then see" two-step.
- Owlbear's **persistent range rings** on selected tokens are the closest
  VTT analog to 40k's "show me 24 inches".
- Door Kickers: **shades of one color** for related concepts (dark blue
  = locked cone, light blue = strafe, green = preview). Don't introduce a
  new hue per concept.

**Today.** `MovementRangeVisual` exists. Range circle is single pale yellow.
No advance/charge differentiation visible. No path coloring during drag.

**Recommendations.**
- **Drag-to-move with budget coloring** (the killer feature):
  - Solid path in faction color from start → cursor.
  - Cumulative distance label at the cursor in inches.
  - Path segment color: green ≤ M, yellow ≤ M+Advance, red beyond.
  - SHIFT to drop a waypoint, ENTER to commit, ESC to cancel.
- **Two-layer range shading** on selected unit:
  - Solid 12% fill within Move distance (where I can stand).
  - Thin outline ring at Move + max weapon range (where I can shoot from).
  - Toggle weapon for the outer ring via the unit panel.
- **Persistent engagement ring** (1") on units in combat — Owlbear aura
  pattern. Already partially built via `EngagementRangeVisual`; make it
  always-on for engaged units.
- **Charge range preview**: at charge declaration, draw a dashed ring at
  12" (max possible 2D6) and a brighter dashed ring at 7" (expected). On
  roll, replace with the actual ring + show the moveable arc.
- **Standalone ruler** (`R` key) for "can I shoot that?" pre-checks with a
  **public/private toggle** — critical in 2-player play where the opponent
  may want to verify a measurement.

**Anti-pattern.** Don't stack one range ring per model in a multi-model
unit. Either render the union, or pick a representative model (closest to
target / unit leader). Ten overlapping rings is the noise problem.

### 6. Line of sight & cover

**Reference findings.**
- Invisible Inc.: hard-edged striped cone for vision; **red tile = visible
  now, yellow tile = noticed (future-tense threat)**. The yellow layer is
  the unique insight — *two states* for threat, not one.
- Advance Wars: terrain bonus rendered as **defense stars on the tile
  itself**, persistent and learnable. Cover isn't a tooltip.
- Frozen Synapse: cone-of-vision rendered *only at waypoints*, not along
  the whole path. Reduces visual noise dramatically.

**Today.** `LoS Debug` toggle button exists. Cover/terrain values not
surfaced diegetically. No visualization of "does this unit have LOS to
that unit".

**Recommendations.**
- **LOS line tool**: on hover of a candidate target while a shooter is
  selected, draw a single line shooter-base → target-base.
  - Green = clear.
  - Yellow = obscured (cover saves).
  - Red = blocked (no shot).
- 40k is omnidirectional so **don't draw vision cones for shooters** — a
  cone would lie. Use the per-target LOS line instead.
- **Cover icons on terrain pieces**: small persistent glyph at the
  geometric center of each terrain footprint: a single shield with `+1`
  / `+2` / `LB` (light/heavy/blocking). Advance Wars terrain-star pattern.
  Never bury cover in a tooltip.
- **LOS Debug toggle stays** as a power-user mode that draws ALL LOS lines
  from the selected unit — keep it, but it should be opt-in (held key,
  not on by default).

**Anti-pattern.** Don't permanently overlay enemy threat ranges by
default. Make it a **held-key threat view** (`Tab` or `Alt`) that paints
all enemy units' shooting ranges + their 12" charge-threat ring. The
Invisible Inc. lesson: permanent overlays compound into illegibility.

### 7. Selection, targeting & dice surfacing

**Reference findings.**
- Wargroove: **damage prediction before commit**. Selecting an attack
  target opens a side panel showing expected damage *before* committing.
- Battle Brothers: hit-chance tooltip on hover with the full modifier
  breakdown (skill − defense ± terrain ± height ± fatigue). Community
  modded this in; the lesson is "always show modifiers".
- Wesnoth: **prospective sidebar** — the side panel previews stats for
  the hex *the cursor is on*, not the unit's current hex.
- Frozen Synapse: **Sim vs. Prime** — explicit preview-vs-commit boundary,
  cleanest in the genre.

**Today.** Weapon Order modal + right-panel "Result" line + game log.
Dice surface in three places, not all simultaneously visible. No
predictive forecast before committing a shot.

**Recommendations.**
- **Hover-forecast tooltip**: when a shooter is selected and the player
  hovers an enemy unit, render a small tooltip near the cursor:
  ```
  Boltgun → Custodian Guard
  6 attacks · BS 3+ · S 4 vs T 6 · AP 0 · D 1
  Expected: 1.3 wounds dealt
  ```
  Source from `RulesEngine` so it stays in sync with abilities/stratagems
  active right now.
- **Center-screen resolution surface** (Wesnoth pattern, but not blocking
  the entire board): a compact panel showing four animated columns
  Hits → Wounds → Saves → Damage. SPACE skips animations.
- **Floating numbers on the affected token**: `-3W` or `-2 models`
  surfaces on the target itself, fades after 2 seconds. Already supported
  by `DamageFeedbackVisual` — make it the primary feedback channel,
  demote the right-panel log to secondary/audit.
- **Persistent right-side roll log** stays as the audit trail (Templar
  Battleforce's killer feature for trust in tabletop fidelity).
- **Explicit commit step**: highlight the target on hover (Hoplite
  pattern), then a single Confirm button or `ENTER` to roll. No "click =
  fire immediately" — that creates the same misclick complaint Door
  Kickers faces.

**Anti-pattern.** Don't make the game log the only feedback channel.
Battle Brothers' damage-type info lived only in the wiki; players never
saw it in-game. Every modifier that affects an outcome must surface in
the forecast tooltip or the resolution panel.

### 8. Roster & information panels

**Reference findings.**
- Battle Brothers + Wesnoth + Templar Battleforce all use a **three-tier
  stat surface**:
  1. On the token (Tier 1): wound count, status icons, model count.
  2. Persistent panel (Tier 2): selected unit's combat-relevant stats —
     M/T/Sv/W/Ld/OC plus weapon profiles. Always visible while a unit
     is selected. Recomputed for the current target (Wesnoth's
     prospective sidebar).
  3. Datasheet modal (Tier 3): full Wahapedia-style profile with
     keywords, abilities, lore. Opens on `i` or right-click. Never auto-pops.
- Templar Battleforce **paginated character sheets** are universally
  panned: don't make the player swap screens mid-action.
- Battle Brothers' **portrait card row** along the bottom works for 12
  units; we have 10–20 multi-model squads, so a left-edge **vertical
  card strip** fits better.

**Today.** Right-side list of all units (`Shield-Captain (1 models)`,
`Custodian Guard (4 models)` …). Selected-unit panel exists
(`UnitStatsPanel.gd`). No three-tier separation; mid-tactical decisions
often require reading the right column carefully.

**Recommendations.**
- **Left-edge vertical roster strip**: portrait + faction color + unit
  name + model count badge + tiny HP chip. Scrollable. Click → camera
  pans + selects; double-click → opens datasheet modal.
- **Exhaustion shading**: units that have completed their action this
  phase go grayscale on the strip *and* on the board. Wesnoth's
  greyed-when-moved is the most readable convention in the genre.
- **Filter chips above the strip**: `All / Can Act / Engaged / Below
  Half`. Optional at 10 units, valuable at 20.
- **Prospective selected-unit panel** (Tier 2): always display the
  selected unit's M/T/Sv/W/Ld/OC + one collapsible weapon row. When the
  player hovers an enemy target, **recompute and re-display** modified
  values (BS after cover, AP vs. enemy Sv, wound roll against T). Wesnoth
  attack-dialog pattern, but lived-in.
- **Datasheet modal** (Tier 3): `i` key. Read-only, dismissable with
  `Esc`. Don't auto-open.

**Anti-pattern.** Don't show static stat profiles when contextual data
exists. If a unit has +1 to hit from Oath of Moment, the panel must say
`BS 2+` (modified), not `BS 3+` (raw) — or it teaches the player to
distrust the panel.

### 9. Color, motion, and visual budget

**Reference findings.**
- **Frozen Synapse palette discipline** is the gold standard:
  - Green = mine, red = theirs, yellow = neutral/warning, blue = grid/UI.
  - The role of each color is invariant across every screen.
- **Door Kickers shades-of-one-color** for related concepts (cone states
  in shades of blue). Don't add a new hue per concept.
- **Wargroove faction palettes** (Cherrystone red, Floran green, Heavensong
  blue, Felheim purple) — saturated, distinct from semantic colors.
- **Battle Brothers Dev Blog #75 lesson**: ornamental textures hurt
  readability. Keep stat surfaces flat and high-contrast.

**Today.** Faction color and player-slot color collide (Custodes yellow
+ blue P1 zone; opponent blue + red P2 zone). Range circles are pale
yellow with no semantic distinction between movement / engagement /
charge. UI chrome uses bright orange highlights on multiple elements
simultaneously.

**Recommendations.**

Adopt a **strict color slot allocation**:

| Slot | Color | Use |
| --- | --- | --- |
| Friendly active player | Teal | P1 zones, P1 selection rings, P1 paths |
| Enemy player | Magenta | P2 zones, P2 selection rings (when shown), enemy threat overlays |
| Faction (per army) | Player-chosen | Token inner ring, unit cards. Independent of P1/P2 slot. |
| Warning / friendly-fire | Orange | AoE templates that can hit own units, overwatch armed, charge possible |
| Confirmed / valid | Green | Movement within M, valid charge target, clear LOS |
| Marginal / partial | Yellow | Within Advance, cover-obscured LOS, threat range |
| Invalid / blocked | Red | Path exceeds budget, blocked LOS, enemy current threat |
| Neutral UI | Pale white | Distance labels, rulers, measurements |

Lock these mappings repo-wide. Document in
`40k/scripts/UIConstants.gd` (or equivalent) so future visual scripts
import the slot rather than picking ad-hoc hex codes.

**Motion budget:**
- Resolution dice animations: ≤ 1.5s, SPACE to skip.
- Token slides on movement: ≤ 0.4s per inch.
- Range overlay fades: 150ms.
- Active-unit pulse: 2s loop at low amplitude.

**Anti-patterns.**
- Faction color collision with semantic color: if a player picks Imperial
  Fists (yellow), our "yellow = warning" overlay collides. **Resolution:**
  semantic yellow renders as a striped/hatched pattern, not solid fill, so
  the texture distinguishes it from faction yellow.
- Bright-orange "this is clickable" rings on every active UI button.
  Reserve one accent color for the *single* primary call-to-action per
  screen.

## Cross-cutting top-10 quick wins

Ordered by expected impact ÷ implementation cost.

1. **Drag-ruler with budget coloring** during movement (green ≤ M, yellow ≤
   Advance, red beyond). Highest tabletop-fidelity payoff. Hooks into
   existing `MovementRangeVisual`.
2. **Top-center six-phase bar with active highlight**. Cheap, transforms new-
   player orientation. Pure scene change in `Main.tscn`.
3. **Hover-forecast tooltip** for shooting/fight (expected wounds before
   commit). Sources from `RulesEngine`. Wargroove + Battle Brothers killer
   feature.
4. **Convert in-tactical modals to side-anchored panels** (Weapon Order,
   Epic Challenge, Wound Allocation). Board stays visible.
5. **Per-tile cover icons** persistently rendered on terrain centers (Advance
   Wars defense stars). Already have terrain data — just render glyphs.
6. **Disposition ring + faction ring separation** on tokens (Foundry
   two-ring). Removes the player/faction color collision.
7. **Exhaustion grayscale** for units that have acted this phase
   (Wesnoth pattern).
8. **Held-key threat overlay** (`Tab`) — paint all enemy threat ranges. Off
   by default to preserve overlay budget.
9. **LOS line tool**: single hover line shooter→target, green/yellow/red.
10. **Strict color slot allocation** documented in `UIConstants.gd`. Foundation
    for everything else; refactor existing visual scripts to consume slots.

## Anti-pattern checklist (avoid all)

- [ ] Faded sub-labels on tokens that no one can read at normal zoom.
- [ ] Range rings stacked per model in a multi-model unit.
- [ ] Vision cones for omnidirectional shooting (40k isn't directional).
- [ ] Permanent enemy threat overlays.
- [ ] Modals covering the board they're asking about.
- [ ] Phase-altering actions sharing click targets with selection (Templar
  Battleforce bug).
- [ ] End-Phase button moving between phases or to top-right.
- [ ] Status profile shown raw when modified values exist.
- [ ] More than two semantic overlays visible simultaneously.
- [ ] Reusing red for both "enemy unit" and "invalid action".
- [ ] Ornamental textures behind stat panels (Battle Brothers Dev Blog #75
  failure mode).
- [ ] Dice outcomes appearing only in the log with no on-token feedback.
- [ ] Unit portraits used to teach rule relationships (Wargroove failure mode).
- [ ] Three or more competing primary call-to-action highlights on screen.

## Reference sources

### 2D tactical games

- Into the Breach — design postmortem & UI deep-dive
  - https://www.gamedeveloper.com/design/-i-into-the-breach-i-dev-on-ui-design-sacrifice-cool-ideas-for-the-sake-of-clarity-every-time-
  - https://www.gdcvault.com/play/1025772/-Into-the-Breach-Design
  - https://www.gameuidatabase.com/gameData.php?id=483
- Hoplite — Magma Fortress design notes
  - http://www.magmafortress.com/p/hoplite.html
  - https://the-art-of-x.writeas.com/game-breakdown-hoplite
- Wargroove — reviews & damage matrix
  - https://gameinformer.com/review/wargroove/inheriting-the-throne
  - https://www.rpgfan.com/review/wargroove/
  - https://wargroovewiki.com/Damage_Matrix
- Advance Wars / Re-Boot Camp — terrain & CO power
  - https://advancewars.fandom.com/wiki/Terrain
  - https://warswiki.org/wiki/CO_Power
  - https://www.nintendolife.com/reviews/nintendo-switch/advance-wars-1plus2-re-boot-camp
- Door Kickers 1 & 2
  - https://strategyandwargaming.com/2021/01/23/door-kickers-2-review-a-classic-in-the-making/
  - https://steamcommunity.com/sharedfiles/filedetails/?id=3426423113
- Frozen Synapse
  - https://en.wikipedia.org/wiki/Frozen_Synapse
  - https://frozensynapse.fandom.com/wiki/Game_Modes
  - https://www.gamedeveloper.com/business/frozen-synapse-prime---our-recreation-and-some-of-the-challenges
- Invisible, Inc.
  - https://www.gamedeveloper.com/design/game-design-deep-dive-alarm-systems-in-klei-s-i-invisible-inc-i-
  - https://anykeytostart.wordpress.com/2015/05/27/invisible-inc/
  - https://invisibleinc.fandom.com/wiki/UI_Tweaks_(Mod)
- Battle for Wesnoth
  - https://wiki.wesnoth.org/UI_Style_Guide
  - https://wiki.wesnoth.org/ThemeSystem
  - https://forums.wesnoth.org/viewtopic.php?p=558892&t=24598
- Templar Battleforce
  - https://steamcommunity.com/app/370020/discussions/0/490123938429860762/
  - https://templarbattleforce.fandom.com/wiki/Overview
- Songs of Conquest
  - https://turnbasedlovers.com/review/songs-of-conquest-1-0-impressions/
  - https://www.gamepressure.com/songs-of-conquest/wielders-and-spells/z4fc74
- Battle Brothers
  - http://battlebrothersgame.com/tactical-combat-mechanics/
  - https://battlebrothersgame.com/dev-blog-75-progress-update-reworked-ui/
  - https://www.nexusmods.com/battlebrothers/mods/283?tab=posts

### Virtual tabletops

- Foundry VTT — tokens, measurement, combat
  - https://foundryvtt.com/article/tokens/
  - https://foundryvtt.com/article/measurement/
  - https://foundryvtt.com/article/combat/
  - https://foundryvtt.com/packages/drag-ruler
- Owlbear Rodeo
  - https://docs.owlbear.rodeo/
  - https://docs.owlbear.rodeo/docs/fog/
  - https://extensions.owlbear.rodeo/auras-and-emanations
  - https://extensions.owlbear.rodeo/ranges
  - https://extensions.owlbear.rodeo/aoe-shapes
- Roll20
  - https://wiki.roll20.net/Toolbar_Overview
  - https://blog.roll20.net/posts/new-measure-tool-shows-aoe-and-shapes/

### Internal evidence

- `40k/test_results/audit_2026_05/screenshots/` — May 2026 audit (deployment,
  command, charge, fight, opportunity attack, engagement zoom, clean board).
- `40k/test_results/playthrough_*.png` — full-turn playthrough screenshots.
- `40k/scripts/` — existing visual primitives (`MovementRangeVisual`,
  `EngagementRangeVisual`, `CoherencyCircleVisual`, `ChargeTrajectoryPreview`,
  `DeepStrikeExclusionVisual`, `DamageFeedbackVisual`, `DiceRollVisual`,
  `ChargeArrowVisual`, `BoardVisual`, `BoardBackground`,
  `UnitStatsPanel`).
- `40k/scenes/Main.tscn` — current scene composition.
