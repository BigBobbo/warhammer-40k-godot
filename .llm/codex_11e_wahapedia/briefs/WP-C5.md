# WP-C5 — Codex: Adeptus Custodes (11e) stratagems (41)

Repository: /home/user/warhammer-40k-godot. You are working in your own git
worktree, on a branch from `claude/gracious-shannon-u3z0mf` AFTER WP-C3 (the
Ka'tah + window additions) merged. Godot project: `40k/`.

Read first:
1. `CLAUDE.md`
2. `.llm/codex_11e_wahapedia/IMPLEMENTATION.md`
3. `.llm/ork_codex_11e_design.md`: all of it. This is the exact pattern you
   replicate: the stratagem window framework, the registry/group-script
   layout, handler API, AI, fixtures, scenarios, the §6.7 framework rules, and
   the §7.2 rulings style.
4. `scripts/40kdc/curated/custodes_codex_11e.json` (41 stratagems, printed
   WHEN/TARGET/EFFECT, inferred `windows` + `_window_review`)
5. `.llm/codex_11e_wahapedia/custodes/RULES.md`

## Scope

All 41 Codex: Adeptus Custodes stratagems (13 detachments) must be usable by
a human player, offered in the correct timing window through the game UI, and
used or declined by the AI (it never stalls).

1. **Dispatcher.**
   - Add `40k/scripts/codex/custodes/CustodesCodex11e.gd` and group scripts,
     with the same API as `OrkCodex11e`.
   - Wire StratagemManager to dispatch `effects_json [{"type":"custom:custodes11e"}]`
     rows to it everywhere it dispatches `custom:ork11e`: implemented marking,
     `can_use_stratagem` order, apply, clear, AI. The CSV rows already carry
     the marker.
2. **Windows.**
   - Confirm or fix every inferred window in the curated file.
   - Add the windows the curated file needs that do not exist yet
     (IMPLEMENTATION.md §3, WP-C5 list).
   - Register them in `KNOWN_WINDOWS`
     (`scripts/40kdc/generate-stratagems.mjs`).
   - Regenerate the rows with
     `cd scripts/40kdc && node generate-stratagems.mjs --only-faction AC`
     (only the AC rows may change; re-run `npm run codex11e` only if you
     changed the curated file's text, and check `git diff` touches only AC
     rows).
   - Stratagems with no event window ("Your Command phase", "Your Shooting
     phase or the Fight phase") stay S-panel stratagems and are gated
     correctly there.
3. **Handlers.** One per stratagem, implementing the printed effect: flags
   with clear points, follow-ups (surge / normal moves, strategic reserves,
   shooting) through the existing follow-up executors.
4. **Rulings.** Record them in `RULINGS.md` (WP-C5).
   - Note: two detachments share stratagem names with different text (IN
     AURAMITE CLAD, SUPERHUMAN FOCUS, SWIFT AS THE EAGLE); csv ids are
     detachment-scoped, so handlers key by csv_id.

## Validation (IMPLEMENTATION.md §5 + Ork design §5)

- **Headless:** `tests/test_custodes_codex_<group>.gd` per group (offer in the
  right window and not others, eligibility, effect A/B with the same seed, CP,
  expiry, once-per), added to `run_pretrigger_tests.sh`.
- **Windowed scenarios:** one per stratagem, `cus11e_<slug>.json`, driving the
  real window with real clicks, asserting the card/button, CP delta and
  effect, with screenshots.
  - For opponent-turn windows, drive the opponent's action.
  - Fixture saves go via a generator like
    `tests/helpers/gen_ork11e_fixtures.gd` (Ork design §6.6).
  - `GODOT_MCP_PORT=9280`, `flock /tmp/codex11e_godot_window.lock`.
- **Full gate:** green apart from the documented baseline failures.
- **Docs:** changelog bullets in `changelog/WP-C5.md`.

Commit on your branch, messages ending with:

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01M5xvNDXsbXePEMCNxmLPLC

Do not push. Final report: per stratagem (window, status), rulings, tests +
pass counts, full gate, scenario PASS list, screenshot paths, anything not
done or not validated.
