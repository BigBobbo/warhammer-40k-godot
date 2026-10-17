# WP-O5 — Codex: Orks (11e) enhancements (38)

Repository: /home/user/warhammer-40k-godot. You are working in your own git
worktree, on a branch from `claude/gracious-shannon-u3z0mf` AFTER WP-O34
merged. Godot project: `40k/`.

Read first:
1. `CLAUDE.md`
2. `.llm/codex_11e_wahapedia/IMPLEMENTATION.md`
3. `.llm/codex_11e_wahapedia/orks/RULES.md` (each detachment's enhancements,
   printed, with points)
4. `orks/wahapedia/Enhancements.csv`
5. `40k/data/40kdc/enhancements.json` / `detachments.json` (Ork entries are
   from 40kdc 1.4.5; check their names and costs against the snapshot)

## Scope

**1. Data check.**
- Compare every Ork detachment's enhancement list (name, points, bearer
  restriction) in the 40kdc data against `orks/wahapedia/Enhancements.csv`
  (38 codex enhancements, Boarding Actions excluded).
- 40kdc 1.4.5 may be stale. If it differs, extend
  `scripts/40kdc/wahapedia-import.mjs` overlay mode to refresh Ork
  enhancements:
  - in place, ids kept
  - `rules_text` added
  - points corrected
- Re-run `npm run codex11e`, and check that `git diff` touches only Ork
  enhancement records.
- Re-run `node verify-wahapedia-import.mjs` and extend it with an Ork
  enhancement check.

**2. Implement all 38 enhancements' effects.**
- Logic goes in `40k/scripts/codex/orks/OrkEnhancements11e.gd`, with thin
  hooks.
- Replace the 10e Ork enhancement code in FactionAbilityManager /
  UnitAbilityManager / ArmyListManager (e.g. Da Biggest Boss +2 W) where the
  codex changed it; delete enhancements no codex detachment has.

**3. Army-construction validation** (bearer restrictions, one of each, the
per-1000-points cap), and the builder UI offering the codex list for the
selected detachment.

**4. AI:** activated enhancements are used or declined without stalling.

## Validation (IMPLEMENTATION.md §5 — all of it)

- **Headless:** `tests/test_ork_enhancements_11e.gd` (one group per
  enhancement), added to `run_pretrigger_tests.sh`.
- **Windowed scenarios:** `ork11e_enh_<slug>.json`:
  - each activated enhancement and at least five passive ones
  - one that equips an enhancement through the real builder UI
  - real clicks, PASS, screenshots
  - `GODOT_MCP_PORT=9680`, `flock /tmp/codex11e_godot_window.lock`
- **Full gate:** green apart from the documented baseline failures.
- **Docs:** changelog bullets in `changelog/WP-O5.md`; rulings in
  `RULINGS.md`.

Commit on your branch, messages ending with:

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01M5xvNDXsbXePEMCNxmLPLC

Do not push. Final report: per enhancement status, data corrections,
rulings, tests + counts, full gate, scenario PASS list, screenshots,
anything not done or not validated.
