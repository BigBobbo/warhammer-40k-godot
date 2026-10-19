# WP-W3 — browser Army Builder on the codex datasheets (player-facing bullets)

- The browser Army Builder now builds from the same data as the game: 40kdc 1.4.5 plus the Codex: Adeptus Custodes and Codex: Orks (11th edition) datasheets. Profiles, points (including the price of later copies), unit sizes, weapons, abilities and leader pairings match the game. Examples: the Shield-Captain is M8" T7 W8 at 180 pts (it was W6 / 110), a Custodian Guard Sodality is 3 models at 240 pts, a Battlewagon is T11 at 160 pts, and Boyz come as 10 (85 pts) or 20 (170 pts).
- Codex wargear that is not a weapon now appears in the builder's Wargear list and travels into the game: the Shield-Captain's Praesidium Shield (+25 pts; swapping to a Castellan Axe or Guardian Spear gives it up), a Vexilla (its +1 OC applies only to a unit that took one), a Kustom Force Field, Paired Krumpas, a Pulsa Rokkit. Priced wargear is added to the unit's points ("per Killsaw", "per Zzap Gun", ...).
- The old Custodes datasheets the codex renamed or dropped (Custodian Guard, Prosecutors, Witchseekers, Vigilators, Venatari / Aquilon / Agamatus Custodians, ...) are no longer offered as new picks. An old list that still has one keeps it, with a warning to swap it for its codex replacement; a pasted pre-codex list moves Custodian Guard, Prosecutors, Witchseekers and Vigilators onto their codex datasheets.
- Upgrades and other enhancements with a qualifier in their name (e.g. Targetin' Gizmos) now reach the game under the name the game uses, so they work in games started from a builder list.
- Exported armies say where their data came from: "40kdc-data 1.4.5 (11th edition) + Wahapedia 11e codex import 2026-10-16 (Codex: Orks, Codex: Adeptus Custodes)" — the same as the game's own army files.
- The builder no longer shows false loadout errors on Ork Boyz.

(Supersedes the WP-C46 note "The browser Army Builder still uses its older Custodes datasheets for unit stats (e.g. Shield-Captain W6)".)

## For the integrator

- Data: `scripts/40kdc/gen_codex_builder_patch.mjs` → `server/public/js/lib/codex-11e-datasheets.mjs` (a diff of 40k/data/40kdc vs the vendored bundle), applied by `data-patches.mjs` `applyCodexDatasheets()` (first line of `applyDataPatches`). It runs at the end of `npm run codex11e` (followed by C46's `gen_custodes_builder_patch.py`) and at the end of `bundle-browser.mjs`. `node gen_codex_builder_patch.mjs --check` exits 1 when the module is stale.
- After merging the remaining packages: re-run `cd scripts/40kdc && node bundle-browser.mjs` (refreshes canon.mjs from the merged .gd tables AND the overlay), then `cd server && npm test` (codex-builder-parity.test.mjs fails if the overlay is stale or the builder data drifts from the game data).
- Expected trivial conflict with WP-O5 in `data-patches.mjs` (both add one call at the top / middle of `applyDataPatches`, plus an import block) and possibly `scripts/40kdc/package.json` (both append a generator to `codex11e`) and `server/package.json` (test file list).
- generate-armies.mjs changes (shared DEFAULT_DATA_SOURCE / bareEnhancementName / wargear-points rule, weapon-line cap): regenerating copies of every 40k/armies file reproduces all committed files byte for byte except the three 1.0.19 snapshots (space_marines, tutorial_custodes, tutorial_orks), which differ exactly as before. Army files were NOT regenerated.

## Builder → game end-to-end (windowed scenario `w3_builder_codex_datasheets`)

The scenario needs a relay server holding the builder-made army. Driver (run from the repo, Playwright Chromium at /opt/pw-browsers):

1. `cd server && PORT=<p> DB_PATH=<tmp>/e2e.db node relay-server.js &`
2. `E2E_BASE=http://localhost:<p> node tests/e2e-codex-datasheets.mjs` — drives the real builder page and saves `WPW3_E2E_Custodes` / `WPW3_E2E_Orks` (33 checks). Optionally also `tests/e2e-custodes-codex.mjs` (saves `WPC46_E2E_Custodes` for `cus11e_enh_builder_cloud_army`).
3. `printf '{"api_url": "http://localhost:<p>"}\n' > 40k/server_config.json` (temporary — never commit it; delete it afterwards).
4. `cd 40k && GODOT_MCP_PORT=9980 flock /tmp/codex11e_godot_window.lock bash tests/run_scenarios.sh tests/scenarios/sp/w3_builder_codex_datasheets.json`
5. Remove `40k/server_config.json`, stop the server.

Result on this branch: e2e 33/33, `w3_builder_codex_datasheets` 20/20 PASS, `cus11e_enh_builder_cloud_army` 19/19 PASS (its Eagle's Eye Shield-Captain is now exported W8 → W9 in game).
