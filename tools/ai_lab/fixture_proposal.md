# V2-5 fixture proposal (not run), rev. 2: build a current `custodes_lions` vs `Orks_2000` fixture first

2026-10-31. Rev. 2 (11:5x UTC) replaces rev. 1 (11:1x) after an adversarial review: verdict needs_changes, with 1 blocker, 5 majors and 8 minors (see Review notes). For the project owner. **Proposal only.** Nothing was built, no game was run, no tracked file was changed and nothing was committed.
Tags: **(M)** measured or computed from saves, logs or records with read-only Python. **(D)** arithmetic on (M) or (E) numbers. **(E)** estimate.

## 1. Answer first

- **Build `asym_custodes_warhorde_2000_postdeploy` first.**
  - P1 (first turn): the current `custodes_lions`, 9 units / 22 models / 1850 pts.
  - P2: the current `Orks_2000` (War Horde), 20 / 106 / 1975, packed on the bench board.
  - Build neither the Orks_2000 mirror (the rev. 1 choice) nor the SW mirror (the V2-5 draft) now.
- **Role.** It is a separate extra gate and never a pooled stratum (§4). It has two jobs:
  - (a) The generality and no-harm check for the V2-4 audit bundle, which is the track that will actually ship. This needs the §4.2 text committed before that arm's first game; otherwise the fixture is information-only for the bundle.
  - (b) The required cross-faction no-harm check for every fix that acts on Orks_2000 units, for example FIX_WAAAGH_ADV_REROLL.
- **Why.** Reach means that the decision unit's *current* datasheet is on the fixture. §2.2 adds the context and the army pairing.
  - **The standard fixtures are stale.** At current profiles they reach **0/44 clear and 0/42 harmful** positions. Every row that rev. 1 counted as "on the bench" (29 clear, 20 harmful) has a model-count or keyword drift (M). This weighs as much as the missing Orks_2000 units.
  - **Option 2 has the widest reach** (M):
    - The current datasheet for **39/44 clear and 38/42 harmful** rows. The Orks mirror has 16/44 and 25/42, the SW mirror 5/44 and 4/42.
    - The whole army pairing for 15/44 clear and 13/42 harmful rows, or 10/44 and 8/42 in its own seat order. The Orks mirror has 8/44 and 10/42; the SW mirror has 0.
  - **It contains the matchup where the named Ork fix measured harmful.** These are the round-1 "Lootas to obj_center" alternatives (M; the move and advance modes are mixed, so treat them as indicative):
    - Orks_2000 vs Custodes: 8 positions; 3 harmful (s7417 -6.67, s7470 -5.50, s7490 -3.83); 0 clear; mean -1.82 VP.
    - Orks mirror: 6 positions; mean +0.06 VP.
  - **It is the critic's most-measured pairing:** 177 jobs, against 153 for the Custodes mirror and 118 for the Orks mirror. By games it is second: 23 against 24 (M).
  - **It is cheaper** than the Orks mirror: 2.5-4 container-min per game against 5-8 (E).
- **No fixture can un-park the Heavy branch of ranged_hold_vs_centre.**
  - The winning `game.patch` acts only in battle round 1. It redirects at most one unit per player, and only a unit whose nearest model is within 2M + 3.5 = 15.5" of the obj_center control range.
  - With the fix in one seat, the V2-1 ceiling is 1 changed decision per game, which is exactly the threshold. The fix would have to fire in all 6 gate games.
  - Zero-game packing check (E):
    - Orks mirror: Lootas A/B/C pack at 21.6 / 18.7 / 17.5" in both seats, so the prediction is **0 fires per game**.
    - Option 2: Lootas A packs at 14.6" (B at 16.7", C at 17.9"). The candidate holds the Orks seat in only 1 game of 2, so the ceiling is **0.5 per game**.
    - SW mirror: the branch is keyword-gated, and Scout Squad A packs at 14.4" in both seats, so the ceiling is 1.0 per game. The 11 logged sweep games with SW contain 0 Scout Squad Heavy holds (M).
  - At F1 (s7462 r1 P2, CONFIRMED-H2 +6.25) the design also moves the sibling unit Gamma, not the measured Alpha (the judge's note in `panel.json`).
  - Un-parking the branch needs a V2-1 amendment, for example a per-opportunity gate for fixes that fire once per game. A new fixture cannot do it.
- **No confirmed finding is actionable on any option.** Here reach requires the datasheet AND the context AND a fix that can be gated (M):

  | | Options 1 and 2: datasheet / context / gateable fix | Option 3 |
  |---|---|---|
  | Rev. 1's 15 off-bench clear findings | 10 / 6 / 0 | 5 / 3 / 0 |
  | The 4 off-bench CONFIRMED-H2 findings | 4 / 2 / 0 | 0 / 0 / 0 |

  Why the 4 confirmed findings fail:
  - s7459 r2 needs the Beastboss attachment.
  - s7484 r1 needs enemy reserves.
  - s7462 r1: see the Heavy branch above.
  - s7459 r1 has no design, and V2-6 stops new rounds.
- **Cost (E).**
  - Engineering: at most about 5.5 h. That is the build analysis's figure for both Ork fixtures together, which was not split.
  - Validation: 1.0-1.6 container-h for 24 games.
  - Each 40-pair look: 3.3-5.3 container-h, i.e. +26-45% on a standard 124-pair look (11.8-12.6, M).
- **Top risks.**
  - 1850 vs 1975 pts inflates F; the seat swap cancels it in E.
  - The Orks always move second.
  - A fix that acts only on Orks_2000 units acts in 1 game of 2 per pair.
  - There are no attachments and no reserves, so reach with context is only 22/44 clear.
  - 420 Ork pts are Legends.
  - 40 pairs detect only large harm, with E below about -3.2 VP (§4.1).

## 2. Evidence

### 2.1 Rosters: 6 fixture saves vs 669 sweep saves (M)

| | Bench (3 standard + 3 reserve fixtures) | Sweeps (75 dirs, 669 saves, 78 games, 565 jobs) |
|---|---|---|
| Data | 40kdc-data 1.0.19 | 40kdc-data 1.4.5 + 11e Wahapedia codex import |
| Custodes | `custodes_lions` at 4dea059 (2026-10-17) or earlier: 11 / 42 / 2000 | The current list in every save: 9 / 22 / 1850 (625 sides). Allarus split mid-game into single-model 'Lion' units that keep 270 pts each, which gives 11/22/2390 (39 sides) and 10/21/2120 (12) |
| Orks | `recon_stomps` (Kult of Speed), old revision: 17 / 77 / 1975. The current `recon_stomps.json` sums to 17 / 75 / **2280**, which is over 2000 | `Orks_2000` (War Horde): 20 / 106 / 1975 in all 523 sides |
| Space Wolves | none | `sw11e_gw_import_2000`: 12 / 59 / 2000 (139 sides) |
| Attachments per side | 0; 1 on the reserve fixtures (Custodes) | Custodes 3, Orks_2000 5, SW 1 |
| Reserves at the start | 0; 4 per side on the reserve fixtures | Varies by seed (s7462: 6 of 20 units, 715 pts) |
| "heavy" strings per save | 0 in all 6 | Custodes mirror 0 (194 saves); Orks_2000 mirror 12-32 (136); Custodes vs Orks_2000 6-10 (200); SW pairings 16-28 (139) |
| Board | take_and_hold_mirror_1 | Official layout per seed: 29 layouts |

- **Units with the same name are different datasheets.**
  - Allarus: 5 models, M5 T7 W4 OC3 on the bench; 3 models, M7 T8 W6 OC2 in the sweeps.
  - Gretchin: 11 models OC2 vs 10 models OC1.
  - Stormboyz: 5 vs 10 models.
  - Mek: Leader vs Support.
- **Missing from all 6 fixtures:**
  - 21 datasheets: 9 from Orks_2000, 10 from SW and 2 from the current Custodes list.
  - 7 weapon-keyword families (HEAVY, ANTI-, LETHAL HITS, CLEAVE, CLOSE QUARTERS, HAZARDOUS, HUNTER), plus SUSTAINED HITS 2.
  - The abilities Infiltrators, Scouts 6", Lone Operative, Stealth, Feel No Pain 6+, Firing Deck 11 and Support.
- **The bench plays the units stored in the save.** The load path is AIBenchmarkRunner.gd:331 -> SaveLoadManager -> StateSerializer -> GameState.load_from_snapshot, and nothing on it re-reads the army files.

### 2.2 Reach by option (M; the 44 clear and 42 harmful rows of `tools/ai_lab/r5_designs/measured_positions.json`)

| Clear / harmful rows reached | Standard bench | **2. Custodes vs Orks_2000** | 1. Orks_2000 mirror | 3. SW mirror |
|---|---|---|---|---|
| Decision unit's current datasheet on the fixture | 0 / 0 | **39 / 38** | 16 / 25 | 5 / 4 |
| ... and the context is on the plain fixture (no flagged attached leader, reserve arrival, reserve-dependent screen or corridor screen) | 0 / 0 | 22 / 24 | 9 / 19 | 3 / 3 |
| ... and the same army pairing, in either seat order | 0 / 0 | 15 / 13 | 8 / 10 | 0 / 0 |
| ... and the same pairing in the fixture's own seat order | 0 / 0 | 10 / 8 | 8 / 10 | 0 / 0 |
| ... and both the same pairing and the context | 0 / 0 | 9 / 11 | 3 / 6 | 0 / 0 |

Rev. 1 used a lenient rule: a unit counted as on the bench if its name, or its renamed Custodes slot, was on a bench roster. By that rule, 15/44 clear findings (31.2% of the clear E-sum) and 22/42 harmful ones are off the bench. The rule counted all 23 Custodes findings as on the bench, although each was measured on a changed profile. It also counted the CONFIRMED Gretchin screen at s7465 (+11.79).

### 2.3 Confirmed counts show where V2-3 looked, not where the AI errs (M)

| Pairing (number of clear rows) | Re-checked at h2 | CONFIRMED-H2 |
|---|---|---|
| Orks_2000 mirror (8) | 6 | 5 |
| Custodes mirror (12) | 2 | 2 |
| Custodes vs SW (4) | 1 | 1 |
| Custodes vs Orks_2000, both seat orders (15) | 0 | 0 |
| SW vs Orks_2000 and SW vs Custodes (5) | 0 | 0 |

- Only 9 of the 44 clear findings were re-checked at h2, and none of the 5 SW-unit findings was. Confirmed counts therefore do not rank the options. If they should, first re-check a sample of the Custodes vs Orks_2000 and SW findings at h2.
- The critic did not find Orks_2000 games worse. Verdicts were flawed in 40.8% of jobs with Orks_2000 on a side and in 40.1% of jobs without.

### 2.4 Examples (M)

| Finding | Value | Why a fixture does not settle it |
|---|---|---|
| s7462 r1 P2, Orks mirror: Lootas hold for the Heavy bonus (the alternative is to Advance to the centre) | CONFIRMED-H2 +6.25 | The design moves Gamma, not the measured Alpha. On every option the packed Lootas also sit outside its window (§1) |
| s7459 r1 P1, Orks mirror: Lootas advance to flip the enemy home objective | CONFIRMED-H2 +4.58 | No design exists, and V2-6 stops new rounds |
| s7459 r2 P2, Orks mirror: Beast Snagga Boyz (Beastboss attached) declare a 28% charge | CONFIRMED-H2 +5.21 | Needs the attachment |
| s7484 r1 P1 and s7465 r1 P2, Orks mirror: Burna Boyz and Gretchin backfield screens | CONFIRMED-H2 +8.00 and +11.79 | Need enemy reserves (reserve track) |
| s7417, s7470 and s7490 r1, Custodes vs Orks_2000: Lootas to obj_center (the alternative) | harmful -6.67, -5.50 and -3.83 | A mirror-only gate never plays this harm |
| s7480 r3 P2, Custodes mirror: Allarus charge target | CONFIRMED-H2 +11.54 | The unit name is on the bench, yet charge_target is PARKED because its fix changed only 0.33 declarations per game |

### 2.5 Parked clusters (line numbers in STATUS.md)

| Cluster | Status | Cause | Does a new fixture help? |
|---|---|---|---|
| ranged_hold_vs_centre | PARKED (L360). The corridor branch was dropped at h2 (L356) | The Heavy branch acts once per player in round 1, inside a 15.5" window | No (§1) |
| marginal_oc | No winner; reach about 0 (L316) | The gates miscount attached leaders, and the bench has 0 attachments (L313-318) | No. It needs an `--attach=ai` builder option |
| Screen clusters | Reserve track (L367) | They need enemy reserves | Only through a `--reserves=ai` variant. The reserve fixtures already fire [SCREEN] 3-6 times per game (L303) |
| charge_target | PARKED (L352) | The fix's narrow gates changed only 0.33 declarations per game pooled (cus 0.5, asy 0.5, ork 0.0), although cus and asy have 16-18 multi-target declarations per game (L289) | No |
| attack_move | Dropped at h2 (L341) | Not a reach problem | No |

## 3. Options compared

| | **2. custodes_lions vs Orks_2000 (recommended)** | 1. Orks_2000 mirror | 3. SW mirror |
|---|---|---|---|
| Name | `asym_custodes_warhorde_2000_postdeploy` | `mirror_warhorde_2000_postdeploy` | `mirror_spacewolves_2000_postdeploy` |
| P1 / P2 (units / models / pts) | 9/22/1850 (first turn) / 20/106/1975 | 20/106/1975 in both seats | 12/59/2000 in both seats |
| Reach (§2.2), clear / harmful (M): datasheet; pairing; pairing + context | 39/38; 15/13; 9/11 | 16/25; 8/10; 3/6 | 5/4; 0/0; 0/0 |
| Rev. 1's off-bench clear findings (of 15), then the confirmed ones (of 4): datasheet / context / gateable fix (M) | 10/6/0; 4/2/0 | 10/6/0; 4/2/0 | 5/3/0; 0/0/0 |
| Sweep-only datasheets added (of 21); missing keyword families added (of 7) | 11; 7, plus SH2 | 9; 7, plus SH2 | 10; 5 |
| [HEAVY] units per side | 0 / 3 (Lootas) | 3 / 3 | 2 / 2 (Scout Squads) |
| Ceiling of the ranged_hold Heavy branch under V2-1 (E, from packing) | 0.5/game | 0 | 1.0/game; 0 Scout Squad holds in the sweeps (M) |
| Games per pair in which an Orks-only fix acts | 1 of 2 | 2 of 2 | none |
| Sweep exposure (M): games (of 78); flawed / all jobs | 23; 77/177 | 15; 42/118 | 0 SW-mirror games; 52/117 for SW jobs |
| Container-min per game (E) | 2.5-4 | 5-8 | 2-3 |
| Validation, 24 games (E) | 1.0-1.6 container-h | 2.0-3.2 | 0.8-1.2 |
| One 40-pair look (E), and its share of a standard look | 3.3-5.3 (+26-45%) | 6.7-10.7 (+53-91%) | 2.7-4.0 (+21-34%) |
| Legality | Orks: 420 Legends pts (Lootas x3, Burna Boyz x2). Custodes: 150 pts unspent | 420 Legends pts per side | 2000 pts at the list's own prices; 1895 at 40kdc table prices |
| Main risks | Points asymmetry; the Orks always move second; half the signal for Ork-only fixes | Slowest; validates mirror-born fixes in-sample; 0 reach for the named fix | Weakest reach; no SW-mirror sweep games; Scout and Infiltrator pre-game moves lost |

Notes:
- **Game times.** The current Ork bench fixture measures 5.0 container-min per game (M). In the one logged critic batch (sweep1, 2026-10-30), the Orks_2000 mirror game ran 24.9 wall-min, against 9.7 and 10.2 for the two Custodes/Orks_2000 games (M; n = 1; a different harness). That is about 2.5 times as long, so option 1 may exceed 8.
- **The mirror's 2x signal.** A mirror gives twice the per-pair signal for an Orks-only fix only if the fix's effect does not depend on the matchup. The one cross-matchup measurement says that it does (§1).
- **z at equal container-hours.** Option 2 gives 0.56-0.89 times option 1's z for an Orks-only fix (D). This is 0.5 x the square root of the cost ratio, because z grows with the square root of the hours, and it assumes an equal per-pair SD.
- **Both Ork fixtures** would cost 3.0-4.8 container-h to validate (E).
- **No mission or board fixture** was considered. Every parked cluster traces back to rosters, attachments or reserves.

Verdict:
- **Option 2 now**, under the §4.2 selection rule.
- **Option 1 later**, only when a named fix passes the zero-game packing and eligibility check on it, with a ceiling of at least 1.0 changed decision per game.
- **Option 3 not now.**

## 4. How it plugs into protocol v2

### 4.1 A separate gate, not a 4th pooled stratum

- Pooled E of the standard bench stays the mean of 3 fixtures. V10's +0.80 (cus +2.92, asy -0.80, ork +0.29), the V12 rule and the V2-6 round gain therefore stay on one scale.
- A 4th pooled stratum would have two costs:
  - A fix that acts only on the new fixture would get half the z (D): (e/4) / (se/2), against e/se, when all se_f are equal.
  - V2-2 would change in the middle of the protocol. Its power table (16/49/78/88%) would need a new simulation, and `decide_v2.py` hardcodes 3 fixtures and the "/ 3".
- **Sensitivity** (E; assumes a per-pair SD of 10.26 VP): se 1.62 / 1.15 / 0.94 VP at 40 / 80 / 120 pairs. At 40 pairs the 95% CI lies wholly below 0 only if E is below about -3.2 VP.
- **Pooling waits for v3.** Pool new fixtures only at v3, together with a rebuild of the stale standard fixtures from current lists. First correct `recon_stomps.json` to a legal 2000-pt list.

### 4.2 Pre-registration text (commit it to protocol_v2.md before any game on the fixture)

> **V2-5b current-list gate track** (written <UTC time>, before any game on the fixture)
> - **Selection rule.**
>   - An extra fixture uses only current, legal (at most 2000 pts) shipped army files.
>   - The first is the shipped pairing with the most critic jobs that is not a standard-fixture pairing: custodes_lions vs Orks_2000 (177 jobs). It uses the seat order with more clear findings, which puts Custodes in P1 (10 findings vs 5).
>   - Another fixture is added only when a named fix passes the zero-game packing and eligibility check on it, with a ceiling of at least 1.0 changed decision per game in the candidate seat.
>   - A parked fix never chooses the fixture.
> - **Fixture.** `asym_custodes_warhorde_2000_postdeploy`:
>   - custodes_lions (git <sha>) as P1 and Orks_2000 (git <sha>) as P2. Each army is packed into its own zone on take_and_hold_mirror_1 by `make_2000pt_fixture.gd`, through Path A (§5). sha256 <...>.
>   - No attachments, and nothing in reserve.
>   - Never rebuilt in place: a rebuild is a new fixture with a new A/A.
> - **Usable only after all of these pass:**
>   - the §5 build-log gates, `fixture_check.py --strict` and the board check;
>   - a 2-pair smoke run: 4 games complete at round 5, with 0 SCRIPT ERROR and M1 = M2 for each seed;
>   - a 10-pair A/A: E = 0.00 exactly, with F and the margin SD reported;
>   - a review with the verdict "usable".
> - **Role.** It is an extra gate. V2-1 and V2-2 on the 3 standard fixtures do not change.
>   - (a) The V2-4 audit bundle, if this text is committed before that arm's first game:
>     - The bundle also needs a 95% CI that is not wholly below 0 on this fixture, at 40 pairs (the look-1 seeds below).
>     - Its E here is reported as generality.
>     - If this text is committed later, the fixture is information-only for the bundle.
>   - (b) Every fix that acts on Orks_2000 units gets the same 40-pair no-harm check before it ships.
>   - (c) A fix whose trigger cannot occur on the standard fixtures, because its keyword or datasheet is in none of the 3 standard saves:
>     - It skips the 124-pair standard no-harm look. Instead, 1 pair per standard fixture must give action logs identical to SHIP vs SHIP, in both seat orders.
>     - It ships only through V2-1 on this fixture: its own decision-level tag must reach at least 1.0 per game over 3 pairs (seeds 96501-96503).
>     - It then needs the V2-2 sequential test on this fixture alone:
>       - looks at 40 / 80 / 120 pairs, as jobs of 8 pairs; seed bases 96000..96080 in steps of 20 for look 1, 96100..96180 for look 2 and 96200..96280 for look 3;
>       - E per seed = (M1 - M2) / 2;
>       - efficacy at z >= 3.710 / 2.512 / 1.993; futility at E <= 0 at looks 1-2.
> - **Not eligible:** the round-1 Heavy branch of ranged_hold_vs_centre. Its ceiling here is 0.5 per game, so it stays PARKED unless V2-1 itself is amended.
> - **Run settings.** `--rules11e`, difficulty 3, `--max-seconds 1500` and at most cores - 1 lanes.
> - **Seeds.** 96000-96999.
>   - The tracked `tools/ai_lab/r4_designs/*/panel.json` files cite round-3 standard-bench seeds from this block (96001-96054 and fire-test seed 96021).
>   - Reusing them on a different fixture, in new season directories, is harmless.
> - **Information-only arms.** Any other arm may also be played here. That result never gates, vetoes or rescues a decision.

## 5. Build and validation steps (proposed commands; none executed)

Before you start:
- **The zero-game check is already done** for all 3 options: `python3 -I /tmp/fxrev/elig.py` (§1).
  - It uses a copy of `/tmp/fxprop/pack_port.py`.
  - `/tmp/review_fx/port_validate2.py` confirms that the port reproduces the committed P1 packings of all 3 bench fixtures to 0.00 px after the 6f07340 x-mirror.
  - A fresh build packs into the current zone, because the builder refreshes the zones with `DZD.get_zones` (`make_2000pt_fixture.gd:155-182`).
- **The /tmp helpers are not durable.** `board_check.py` imports from the hardcoded path /tmp/fxprop, so keep a copy there.
- **Set `XDG_DATA_HOME` for builds only.** `run_lanes.userdata_dir()` hardcodes `~/.local/share/godot/app_userdata/40k` for bench runs.

```bash
# 0. Once per fresh clone (builds the global class cache)
export PATH="$HOME/bin:$PATH"; cd /home/user/warhammer-40k-godot
godot --headless --path 40k --import

# 1. Path A (no code change): an isolated user dir whose builder shell (const SHELL =
#    "mirror_custodes_postdeploy", read from user://saves) is the bench fixture -> take_and_hold_mirror_1.
U=/tmp/fxbuild/godot/app_userdata/40k/saves; mkdir -p $U
cp 40k/tests/saves/mirror_custodes_2000_postdeploy.w40ksave $U/mirror_custodes_postdeploy.w40ksave
cp 40k/tests/saves/mirror_custodes_2000_postdeploy.meta     $U/mirror_custodes_postdeploy.meta

# 2. Build (option 1 later: --mirror=Orks_2000 --out=mirror_warhorde_2000_postdeploy).
#    NEVER build without step 1: the board would be legacy_fallback_mirror_1.
FX=asym_custodes_warhorde_2000_postdeploy
XDG_DATA_HOME=/tmp/fxbuild godot --headless --path 40k -s tests/make_2000pt_fixture.gd -- \
    --p1=custodes_lions --p2=Orks_2000 --out=$FX > /tmp/fxbuild/$FX.log 2>&1; echo "exit=$?"

# 3. Build-log gates
L=/tmp/fxbuild/$FX.log
grep -c "Save files will be stored at: /tmp/fxbuild/godot/app_userdata/40k/saves/" $L  # >= 1
grep -c "Loaded layout 'take_and_hold_mirror_1'" $L                                     # >= 1
grep -c "falling back to" $L                                                            # 0
grep -c "SCRIPT ERROR" $L                                                               # 0
grep -E "PM-F3 board refresh|P1 packed|P2 packed|units, .* models|coherency gate|models out of place" $L

# 4. Offline checks on the built file
S=$U/$FX.w40ksave
python3 tools/ai_lab/fixture_check.py $S --strict
python3 -I /tmp/fxprop/board_check.py $S --ref=40k/tests/saves/mirror_custodes_2000_postdeploy.w40ksave
python3 -I /tmp/fxprop/save_summary.py $S

# 5. Install as an UNTRACKED file (commit only after the review). The runner never refreshes a stale user:// copy.
cp $U/$FX.w40ksave $U/$FX.meta 40k/tests/saves/
rm -f ~/.local/share/godot/app_userdata/40k/saves/$FX.w40ksave ~/.local/share/godot/app_userdata/40k/saves/$FX.meta
python3 tools/ai_lab/fixture_check.py $FX --strict     # ai_versions.py never runs this gate itself

# 6. Smoke run: the shipped AI in both seats, 2 seeds (4 games)
AI_LAB_KEEP_LOG_GREP='SCRIPT ERROR' python3 tools/ai_lab/ai_versions.py run --base HEAD --cand HEAD \
    --tag SMOKE_ACW --pairs 2 --seed-base 96900 --rules11e --fixture $FX --lanes 2 --max-seconds 1500 \
    --season bench_data/smoke_acw
ls bench_data/smoke_acw/_logs/*.gz 2>/dev/null          # expect none: a .gz is a game that did not complete
grep -c "SCRIPT ERROR" bench_data/smoke_acw/_logs/*.log  # 0 in each file

# 7. A/A, 10 pairs: F, margin SD, determinism
python3 tools/ai_lab/ai_versions.py run --base HEAD --cand HEAD --tag AA_ACW --pairs 10 --seed-base 96800 \
    --rules11e --fixture $FX --lanes 3 --max-seconds 1500 --season bench_data/aa_acw

# 8. Each gated arm (role a or b): 40 pairs = 5 jobs of 8 pairs at seed bases 96000/96020/96040/96060/96080.
#    Give every job its own tag and season: a shared one silently reports the first candidate's margins.
python3 tools/ai_lab/ai_versions.py extract SHIP=<shipped sha> ARM=<arm sha>
python3 tools/ai_lab/ai_versions.py run --base SHIP --cand ARM --tag ARM_ACW_96000 --pairs 8 --seed-base 96000 \
    --rules11e --fixture $FX --lanes 3 --max-seconds 1500 --season bench_data/acw_arm_96000

# 9. Decide with a one-fixture copy of .ai_lab_work/decide_v2.py. Change all of these:
#    - read "per_seed" from <season>/<tag>.summary.json (written by ai_versions.py), not BENCH_RESULT
#      lines from .ai_lab_work/bench_results/*.txt;
#    - NEED = {'acw': 40} and look base 96000;
#    - "if len(have) < 3" -> "< 1"; pooled SE = se_f (drop the "/ 3").
```

Pass criteria:

| Step | Pass when |
|---|---|
| 2-3 | All of these hold: |
| | - exit code 0, and the four grep counts match the comments; |
| | - "P1 packed 22 model(s)" and "P2 packed 106 model(s)"; |
| | - "P1: 9 units, 22 models, 1850 pts — Adeptus Custodes / Lions of the Emperor" and "P2: 20 units, 106 models, 1975 pts — Orks / War Horde"; |
| | - "coherency gate: all units coherent as deployed" and "models out of place: 0". |
| | For option 1 the packing lines are "P1 packed 106 model(s)" and "P2 mirrored 106 model(s) by 180-degree rotation". |
| 4 | All of these hold: |
| | - fixture_check reports PASS with no warnings; |
| | - board_check prints "RESULT: PASS" and "board identical to mirror_custodes_2000_postdeploy"; |
| | - board_check counts [HEAVY] weapon entries as P1 0 / P2 3; |
| | - save_summary shows every unit with st=2, no attached_to and no reserve. |
| 6 | 4 games complete at round 5, M1 = M2 for each seed, 0 SCRIPT ERROR, no .gz files. |
| 7 | `AA_ACW.summary.json` shows E = 0.00 with se 0. Record F and the margin SD. |
| Afterwards | An adversarial review of the board, rosters, packing and smoke logs gives the verdict "usable". Record the fixture sha256 in the amendment. |

Optional variants:
- **Reserves variant**: `--base=$FX --reserves=ai --out=asym_custodes_warhorde_2000_reserves_postdeploy`.
  - The builder then runs the AI's Formations step: attachments, embarkations and reserves. This is the only way to restore the missing context.
  - Run fixture_check without `--strict`, because any reserve gives a warning.
- **Path B** (a lasting fix that edits a tracked file; not done): add `--shell=<fixture>` to the builder, and make it fail on `legacy_fallback_mirror_1`.

## 6. Risks

**Bias toward the critic's sample.** The controls are:
- The §4.2 rule chooses fixtures, not the parked fix that needs reach.
- Every Ork fix gets a cross-faction no-harm check (§4.2b).
- A fix that cannot fire on the standard fixtures gets the identical-action-log check (§4.2c). A 124-pair look would cost 11.8-12.6 container-h and could not detect harm: the 6 bench saves have 0 "heavy" strings, so a [HEAVY] fix has E = 0 there by construction.
- The 25 harmful positions whose decision unit is an Orks_2000 unit are decision-replay guardrails for every Ork fix (M).
- Generality across [HEAVY] carriers is **untested**. Only the Lootas would be on a fixture. These shipped army files have [HEAVY] weapons (M; the picker lists every `40k/armies/*.json`):
  - Lootas: Orks_2000, battlewagons, orks, orks_taktikal.
  - Scout Squads: sw11e_gw_import_2000.
  - Intercessor and Infiltrator Squads: space_marines.
  - 14 datasheets in sm11e_codex_test; Intercessors in sw11e_codex_test.

  No shipped file fields a Big Mek with Shokk Attack Gun.

**Asymmetry.**
- 1850 vs 1975 pts inflates F; the seat swap cancels it in E.
- The Orks always move second. The findings from games where the Orks moved first (5 clear, 5 harmful) need a second build with the seats swapped.

**Fidelity.**
- The fixture has no leader attachments, and nothing in reserve. The sweeps attach 5 leaders per Orks_2000 side and 3 per Custodes side.
- Other differences from the sweeps: a packed deployment, empty Battlewagons, no Infiltrator or Scout pre-game moves, and one board instead of an official layout per seed.
- The engine supports Kunnin' Infiltrator, but no sweep save shows the AI using it. Boss Snikrot and Kommandos are DEPLOYED (status 2) in all 523 Orks_2000 sides, and AIDecisionMaker.gd:6759-6768 cancels the placement.

**Legality and data drift.**
- 420 of the 1975 Ork pts are Warhammer Legends (source 000000377): Lootas x3 and Burna Boyz x2.
- Battlewagons load as 32 mm round bases.
- The army files have changed under the bench before. Freeze the fixture by its sha256 and by the army files' git shas.
- fixture_check does not check points against datasheets, Legends status, unit sizes or board geometry.

**Harness and board.**
- The default `--max-seconds 900` risks timeouts; use 1500.
- `ai_versions.py` skips fixture_check, and the runner never refreshes a stale `user://saves` copy.
- `decide_v2.py` assumes 3 fixtures (§5, step 9).
- fixture_check's docstring lists a `--bench-only` flag that argparse does not define.
- The builder's default shell gives legacy_fallback_mirror_1, where the no-man's-land objectives sit 5.63" inside the deployment zones. That fixture still passes `--strict`.
- Reserves variant only:
  - `_is_valid_reinforcement_position` has no per-model wall or oval check;
  - destroyed reserve units keep IN_RESERVES.

## Review notes

**Applied**
- The blocker: §1, §3 and §4.2 now give the packing and eligibility prediction for every option.
- The 5 majors:
  - Reach requires the datasheet, the context and a fix (§1, §3).
  - Confirmed findings are reported out of re-checked findings and no longer rank the options (§2.3).
  - A matchup-level reach row, the "2x" qualifier and the cross-faction check are added (§2.2, §3, §4.2b).
  - The vacuous controls are replaced by the identical-action-log check, with the real [HEAVY] carriers listed (§4.2c, §6).
  - One reach definition is used throughout, led by current profiles, with the stale bench as a finding (§1, §2.2).
- All 8 minors:
  - seeds (§4.2);
  - "heavy" per matchup (§2.1);
  - the 1.4 lines/game Poisson figure is removed: all 24 sweep games stopped at round 4 and the smoke game at round 2, and the packing check replaces it;
  - Snikrot (§6);
  - costs and arithmetic (§3);
  - the charge_target cause (§2.5);
  - roster states and the recon_stomps total (§2.1);
  - the decide_v2 changes (§5).
- The first-choice opinion: option 2 first; the bundle role; the selection rule; the offline check before choosing; ranged_hold treated as a V2-1 question.

**Corrected or partly applied**
- **"Option 3 has no Lootas."** True, but the branch is keyword-gated. Scout Squad A packs at 14.4", inside the window, in both seats. Its ceiling is 1.0 per game, and the sweeps logged 0 Scout Squad Heavy holds, so the conclusion stands.
- **"Most-played pairing: 23 games."** This holds by jobs (177 vs 153). By games the Custodes mirror has 24, but it is a standard-fixture pairing that is rebuilt only at v3, so the rule counts jobs and excludes standard pairings.
- **[HEAVY] carriers.** The review's list omits `sm11e_codex_test.json` and `sw11e_codex_test.json`, which the picker also lists.
- **"Almost every finding is off the bench."** By the reach table's own drift column, every finding is: 0/44 and 0/42.
- **Option 1 game time.** Widened to 5-8 container-min as asked. The review's "~3.0 container-min per bench asym game" was not re-derived and is not used.

**Rejected outright:** none.

---
**Sources**
- **Rev. 1 inputs:**
  - `/tmp/roster_audit/`;
  - `/tmp/fixture_reach/{table.csv,rows.json,cluster_units.json}`;
  - `/tmp/fxprop/*.py`;
  - `.ai_lab_work/STATUS.md` (line numbers as of 11:24 UTC);
  - `tools/ai_lab/protocol_v2.md`;
  - `tools/ai_lab/tuning_track_proposal.md:150-156`: a look costs 11.8-12.6 container-h; an Ork game takes 5.0 container-min; the per-pair SD of 10.26 VP is assumed.
- **Review scripts re-run:** `/tmp/review_fx/{pack_lootas2,port_validate2,jobs2}.py`.
- **Rev. 2 re-checks** (read-only, `/tmp/fxrev/`):
  - `elig.py`: packing and eligibility;
  - `options_reach.py`, `onbench.py`: reach levels and drift;
  - `h2cov.py`: h2 coverage;
  - `lootas_centre2.py`: the Lootas-to-centre alternatives;
  - `sweepscan.py`: "heavy" strings, roster states, Snikrot;
  - `heavy_armies.py`: [HEAVY] carriers;
  - `profiles.py`: same-name profiles;
  - `zones.py`: zones.
- **Other sources:**
  - the game-log timestamps in `40k/tools/llm_critic/runs/sweep_logs_sweep1/`;
  - `tools/ai_lab/r5_designs/ranged_hold_vs_centre/{game.patch,panel.json}`;
  - `AIDecisionMaker.gd:1959` (ADVANCE_EXPECTED_EXTRA_INCHES 3.5) and `:6759-6768`;
  - `.ai_lab_work/decide_v2.py`;
  - `tools/ai_lab/ai_versions.py:136`.
- **Corrections carried over from rev. 1:**
  - (a) The "s7406 r2 charge" is s7415 r2 P1.
  - (b) board_check counts weapon entries, so the SW mirror shows [HEAVY] 6/6.
  - (c) The `mirror_warhorde_...` name avoids a one-character clash with `mirror_orks_2000_postdeploy`.
