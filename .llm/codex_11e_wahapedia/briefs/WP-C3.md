# WP-C3 — Codex: Adeptus Custodes army rules

Repository: /home/user/warhammer-40k-godot. You are working in your own git
worktree, on a branch created from `claude/gracious-shannon-u3z0mf`. Godot
project: `40k/`.

Read first, in this order:
1. `CLAUDE.md`
2. `.llm/codex_11e_wahapedia/IMPLEMENTATION.md` (the contract: layout, windows, ownership, validation bar)
3. `.llm/codex_11e_wahapedia/PLAN.md` §C3
4. `.llm/ork_codex_11e_design.md` §3, §6
5. `.llm/codex_11e_wahapedia/custodes/RULES.md` ("Army rules")

## Scope

Implement the Codex: Adeptus Custodes (11e) army rules exactly as printed in
`custodes/RULES.md`.

1. **Martial Ka'tah.**
   - At the start of YOUR Command phase every friendly ADEPTUS CUSTODES unit
     with the ability is readied. A unit that is still readied in the
     opponent's turn can use a ka'tah then.
   - While readied, the unit may use ONE ka'tah ability, in that ability's
     WHEN; it is then no longer readied.
   - The six abilities:
     - **Conservai** (your Command phase): until end of turn, engaged or
       battle-shocked doesn't prevent starting an action, and starting an
       action doesn't prevent shooting.
     - **Calistus** (your Movement phase, when selected to move): normal,
       advance and fall-back moves can move through all models.
     - **Salvus** (your Shooting phase, when selected to shoot): ignore
       modifiers to BS, hit and wound rolls.
     - **Dacatarai** (start of the Fight phase): melee attacks vs
       non-MONSTER/VEHICLE re-roll hit rolls of 1.
     - **Kaptaris** (start of the Fight phase): melee attacks that target the
       unit are -1 to hit.
     - **Rendax** (Fight phase, when selected to fight): melee
       [LETHAL HITS: MONSTER/VEHICLE].
   - Offer each one in the right window to the human: a ka'tah card/panel in
     the window dialog, or a dedicated panel. Show the readied state on the
     unit (token marker or unit card), and let the AI choose (never stall).
   - **Favoured Ka'tah API** for the detachments package: a hook
     `CustodesKatah.favoured_katah(player) -> String` and an "extra effect"
     callback that `CustodesDetachments.gd` will fill in. Ship a stub that
     returns "" and document it.
   - Add the windows listed for C3 in IMPLEMENTATION.md §3.
   - Delete the old 10e/1.0.19 stance system: the Dacatarai/Rendax picker,
     `KatahStanceDialog`, `apply_katah_stance` / `clear_katah_stance`, and the
     FightPhase Ka'tah branches. Keep nothing that is not codex.
   - **Master of Ka'tahs** (Shield-Captain datasheet ability, "Once per battle
     round, per unit: if this unit is not readied, it is readied") belongs to
     this package, because it is part of the readied economy.
2. **Aegis of the Emperor:** friendly ADEPTUS CUSTODES units with the ability
   have Feel No Pain 5+ against mortal wounds. It must apply on every
   mortal-wound path (devastating wounds, hazardous, deadly demise, stratagem
   MWs, ...). Make sure it does not stack wrongly with other FNPs: take the
   best applicable.
3. **Aquila Commander:** at the start of the battle round, if a model with
   this ability is your WARLORD, gain 1CP. Respect the core rules' CP gain cap
   if the game implements one.
4. **Daughters of the Abyss** (ANATHEMA PSYKANA units):
   - FNP 3+ against psychic attacks.
   - **Psychic Null (Aura):** friendly ADEPTUS CUSTODES units within 6" have
     FNP 5+ against psychic attacks.
   - Replace whatever the old implementation does.
5. **Anathema Psykana:** an ANATHEMA PSYKANA model cannot be the WARLORD
   (army validation warning/error per the existing validation style), unless
   the detachment rule says so (Null Maiden Vigil — leave a hook).

Army data already carries these abilities (`meta.abilities`: "Martial Ka'tah"
with codex text, "Aegis of the Emperor", "Aquila Commander", "Daughters of
the Abyss", "Master of Ka'tahs"). Do not regenerate data.

## Validation (see IMPLEMENTATION.md §5 — all of it)

- `tests/test_custodes_army_rules_11e.gd`, added to `run_pretrigger_tests.sh`.
  It must cover:
  - readied at Command start, and not for the opponent's units
  - each ka'tah offered only in its window and only while readied
  - one use un-readies the unit; a second ka'tah is refused
  - each effect A/B with the same seed
  - expiry
  - Master of Ka'tahs re-readies once per battle round
  - Aegis on several MW sources
  - Aquila CP only when the warlord has it
  - Daughters 3+/aura 5+ only vs psychic
  - the AI picks without stalling
- Full `bash 40k/tests/run_pretrigger_tests.sh`. Known pre-existing failures on
  this branch are listed in `.llm/codex_11e_wahapedia/BASELINE.md` (if it
  exists); anything else is yours. Tests of the removed 10e stance system get
  retired in `RETIRED_TESTS.md` with reasons.
- Windowed scenarios that drive real clicks:
  - `cus11e_katah_rendax_selected_to_fight`
  - `cus11e_katah_kaptaris_fight_start`
  - `cus11e_katah_calistus_move`
  - `cus11e_aquila_commander_cp`
  - and one for the readied marker UI

  Each scenario passes via `run_scenarios.sh`. Capture screenshots of each
  effect. Use `GODOT_MCP_PORT=9180` and
  `flock /tmp/codex11e_godot_window.lock` for windowed runs.
- Changelog bullets go in `.llm/codex_11e_wahapedia/changelog/WP-C3.md`.
  Rulings go in `.llm/codex_11e_wahapedia/RULINGS.md` (WP-C3 section).

Commit on your branch with clear messages, ending with:

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01M5xvNDXsbXePEMCNxmLPLC

Do not push. Final report: what was implemented per rule, rulings, tests with
pass counts, full-gate result, scenario PASS output, screenshot paths, and
anything not done or not validated (stated plainly).
