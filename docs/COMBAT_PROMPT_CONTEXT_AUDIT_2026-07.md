# Combat Prompts — "Who is attacking whom" & Board-Visibility Audit (2026-07)

**Trigger**: during the AI's shooting phase the defender's *Allocate Attacks*
window said only "Big shoota: 2 wound(s) to save" — the weapon was named but
not the UNIT shooting it, and the window (plus a 55% full-screen dim) sat over
the middle of the battlefield. Owner directive: every prompt that interrupts
play must make clear **who is attacking**, **who is being attacked**, and must
**not cover the game board**.

**Principles applied** (extends `SHOOTING_MULTI_TARGET_UX_AUDIT_2026-07.md`
B1/B2 — chips-on-board + docked resolution surfaces):

1. An attack interaction names BOTH units, always — never only the weapon.
2. Decision surfaces dock at a screen edge (right HUD column preferred, same
   slot the attacker's resolution dock uses); the battlefield stays visible.
3. The battlefield itself should show the interaction — outline attacker and
   target on the board and link them, so the answer to "who is shooting me?"
   is visible spatially, not only as text.
4. No full-screen dims during resolution decisions.

---

## 1. Fixed on this branch

### 1.1 AllocationGroupOverlay (defender saves — shooting AND melee) — the report
- **Attacker context**: new `AttackerInfo` line under the title — "Shot by
  ‹unit›" / "Struck in melee by ‹unit›" (resolved from `shooter_unit_id`,
  which `prepare_save_resolution` / `prepare_melee_save_resolution` always
  carry). The casualty-pick banner also names the attacker ("hit by ‹unit›").
- **Board stays visible**: the decision panel (order → re-roll → results)
  moved from screen-center to the right HUD column (the `Center` container is
  re-anchored; scenario node paths unchanged). The full-screen dim is gone
  (node kept hidden for compatibility; the full-rect root still swallows
  stray clicks so the modality is preserved). The casualty-pick panel moved
  to the same right-column slot — previously top-center, where it could cover
  the enemy half of the board.
- **Board context visual**: new `AttackContextVisual` (Node2D, board space)
  drawn while the overlay is up — pulsing red outline around every attacker
  model, gold outline around every defending model (attached characters
  included via the combined allocation unit), dashed red arrow
  attacker → target (skipped in base contact). Freed with the overlay.

### 1.2 FightSequenceDialog (staged melee hit/wound rolls)
Header named only the fighter ("X — melee attacks"). Now appends the
defender(s) from the staged assignments: "X — melee attacks vs Y, Z".

### 1.3 StratagemDialog (defender's reactive-stratagem window)
Header said "Your units are being targeted!" without naming the attacker. Now
best-effort resolves the live phase's `active_shooter_id` (set on every peer,
since all peers replay the attacker's CONFIRM_TARGETS): "Your units are being
targeted by ‹unit›!". Falls back to the generic header when unavailable.

---

## 2. Inventory — remaining interrupt surfaces

Assessment key: **Names units?** = does the prompt identify the units the
interaction is between (n/a for pickers that only involve your own units)?
**Board?** = does it keep the board visible (docked/compact) or cover the
center?

| Surface | Names units? | Board? | Verdict |
|---|---|---|---|
| AllocationGroupOverlay | ✅ both + board outlines | ✅ right-dock, no dim | fixed (this branch) |
| FightSequenceDialog | ✅ both (this branch) | ❌ center AcceptDialog | **follow-up F1** |
| StratagemDialog (reactive) | ✅ attacker (this branch) + target list | ❌ center | acceptable (short-lived decision), F1 candidate |
| FireOverwatchDialog | ✅ "Enemy unit: X" + your eligible units | ❌ center + countdown | acceptable; F1 candidate |
| CommandRerollDialog (charge etc.) | ✅ unit + context text | ❌ center | acceptable (brief) |
| TankShockDialog / TankShockResultDialog | ✅ vehicle + target pick | ❌ center | acceptable |
| HeroicInterventionDialog | ✅ "Enemy unit that charged: X" | ❌ center | acceptable |
| EpicChallengeDialog | ✅ target CHARACTER named | ❌ center | acceptable |
| KrumpAndRunDialog | ✅ fell-back enemy named | ❌ center | acceptable |
| GrenadeTargetDialog / GrenadeResultDialog | ✅ unit pickers staged | ❌ center | acceptable |
| CounterOffensiveDialog | ⚠️ "An enemy unit has just fought" — WHICH unit is not named (caller doesn't pass it) | ❌ center | **follow-up F2** |
| AttackAssignmentDialog (melee declaration) | ✅ own unit + target pick | ❌ center | superseded when F1 docks the fight flow |
| WeaponOrderDialog / NextWeaponDialog | ✅ (fixed in shooting audit 1.4) | ❌ center | **MP-only** since B2; retired when the MP dock port lands |
| WoundAllocationOverlay (10e per-wound) | ✅ target only | ❌ center modal + dim | legacy — unreachable at edition 11 (the shipped default); retire with the 10e code path |
| SweepingAdvanceDialog | ✅ unit + move type | compact, board interactive | good pattern (drag on board while dialog shows status) |
| BattleShockConfirmationDialog | ✅ lists untested units | ❌ center | fine (end-of-phase confirm, not mid-attack) |
| FightSelectionDialog / PileInDialog / ConsolidateDialog / EndFightConfirmationDialog | own-unit pickers | mixed | pile-in/consolidate pickers already moved into the right panel (#657); same direction applies to the rest of the fight flow (F1) |

Screen-edge/table-flow dialogs not audited in depth (deploy, missions,
save/load, lobby, game-over): they run outside combat resolution where
covering the board is not a defect.

## 3. Follow-ups

- **F1 — Fight-phase resolution dock**: port the B2 docked-resolution design
  to the Fight phase — FightSequenceDialog (and the melee stack around it)
  becomes a right-HUD dock; the new AttackContextVisual can mark
  fighter/defenders on the board for the whole activation, not only during
  saves. This is the melee sibling of the shipped shooting dock.
- **F2 — CounterOffensiveDialog**: pass the unit that just fought through
  `FightPhase`'s counter-offensive signal so the header can name it.
- **F3 — MP dock port** (already tracked in the shooting audit): networked
  play still uses WeaponOrderDialog/NextWeaponDialog; the defender-save
  right-dock shipped here applies in MP as-is (the overlay is peer-local).
- **F4 — Overwatch/reactive prompts as docked banners**: FireOverwatch and
  StratagemDialog could become right-column banners with board outlines of
  the triggering enemy unit (AttackContextVisual is reusable for this).
