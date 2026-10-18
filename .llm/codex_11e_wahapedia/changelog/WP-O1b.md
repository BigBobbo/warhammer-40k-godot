# WP-O1b — Codex: Orks weapon kits (player-facing bullets)

- Tankbustas now carry their Codex: Orks kit: every Tankbusta has a Busta Rokkit Launcha and a Gitstikka (no more Close combat weapon), the Nob a Choppa and Rokkit Pistols.
- Warbikers now carry their Codex: Orks kit: the Biker Nob has a Kustom Choppa and a Dual Kombi-rokkit, every Warbiker a Choppa and a Dual Dakkagun (the old Twin dakkaguns, Close combat weapons and Nob weapon options are gone).
- The Runtherd's melee weapon is now the codex "Runtherd's Toolz", and Nazdreg no longer lists his Kustom Blasta X melee profile twice.
- Fixed swapped weapon profiles: the Dual Kombi-rokkit's Dakkagun (18" A6 S5) and Busta Rokkit (24" A2 S10 D3), and the Kannon's Frag and Shell (Gunwagon, Gargantuan Squiggoth) each show and fire their own numbers.
- Deffkoptas fire their Rokkit Launcha again (they were left with only a Slugga), and a roster that names a multi-profile weapon once ("3x Rokkit Launcha") is read correctly.
- 20-model Boyz mobs: both Nobs now fight with a Kustom Choppa (the second Nob used to get a Boy's Choppa).
- Old saves and pre-codex army lists keep their old Boyz, Tankbustas and Warbikers loadouts (old Boyz mobs had lost their per-model weapons).
- The shipped Ork army lists (Orks_2000, Orks_2000_upload, Orks_Upload_Mar7, battlewagons, recon_stomps, ork11e_codex_test, orks, orks_taktikal) are updated to these kits; points are unchanged. The Adeptus Custodes 1995 list's Allarus Custodians now carry their Castellan Axes (the list did not say how many models took one).

## For the integrator

- Pipeline: `cd scripts/40kdc && npm run codex11e` is idempotent on this branch (re-run: no diff). `node verify-wahapedia-import.mjs` PASS (it now also checks a named profile carries its own numbers; fails on the old swapped data).
- legacy-kits.mjs: new `--units a,b` (per-datasheet merge; datasheets already frozen are kept) and `--from "<dataset>"` (stamped as `frozen_from`). This WP ran `node legacy-kits.mjs --old <0491aa18 unitCompositions/wargearOptions> --faction orks --tag 1.0.19 --from "40kdc-data 1.4.5" --units tankbustas,warbikers,runtherd,nazdreg`.
- Army files regenerated with `node generate-armies.mjs` on every 40k/armies file except tutorial_*, space_marines, adeptus_custodes_roster_stubs. Unit keys unchanged (the AI plans' references stay valid); points unchanged in every file; recon_stomps stays 2280/2000 (known).
- Gate: + tests/test_loadout_resolution.gd, tests/test_transport_audit_2026_07.gd.
- New windowed scenario: `o1b_codex_kits`.
