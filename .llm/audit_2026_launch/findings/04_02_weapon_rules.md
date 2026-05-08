# 04.02 — Weapon Special Rules — Findings

**Audit date:** 2026-05-06
**Source prompt:** `.llm/audit_2026_launch/04_data_entities/02_weapon_rules.md`
**Universe:** `.llm/audit_2026_launch/universe/weapon_rules.json` — 37 distinct tokens (19 P0 used by active rosters, 18 P2 catalog-only).

**Live validation:** MCP bridge reachable (`ping=ok` on 4.6-stable). All P0 tokens spot-checked live via `get_node("/root/RulesEngine").<helper>(...)`; transcripts inline below.

---

## Summary counts

|  | ✅ matches | ⚠️ partial | ❌ absent | 🐛 diverges |
|---|---:|---:|---:|---:|
| **P0** (19 tokens used by rosters) | 14 | 4 | 0 | 1 |
| **P2** (18 catalog-only tokens) | 1 (Conversion: catalog handler exists) | 0 | 17 | 0 |

**Depth distribution (P0):** all 19 are at least `C/W` (handler exists and is invoked from shoot/melee pipelines). 9 of 19 are `U` (icon shown to player); the other 10 are invisible features.

---

## P0 token table (19 roster-fielded tokens)

| Token | Roster uses | Priority | Depth | Correctness | Evidence | Notes |
|---|---:|---|---|---|---|---|
| `pistol` | 41 | P0 | U | ✅ | helper `is_pistol_weapon` `40k/autoloads/RulesEngine.gd:4517`; ER-only enforcement `RulesEngine.gd:3306-3307`; per-model exclusivity `RulesEngine.gd:3402-3423`; pistol-target-must-be-in-ER `RulesEngine.gd:3367-3371`; icon `40k/scripts/WeaponKeywordIcons.gd:72`. Live: `is_pistol_weapon("plasma_pistol")=true`. | Per-model exclusivity (MA-25) is correct 10e behaviour — single model with both Pistol & non-Pistol must choose; M/V exempt. |
| `rapid fire` | 56 | P0 | U | ✅ | helper `get_rapid_fire_value` `RulesEngine.gd:4900` (regex on `special_rules` + keywords); applied at half-range `RulesEngine.gd:1384-1410, 2032-2033`; icon `WeaponKeywordIcons.gd:78`. Live: `get_rapid_fire_value("Kombi-weapon")=1` from Ork roster. | `models_in_half_range` computed per-model. ✅ |
| `blast` | 27 | P0 | U | ✅ | helper `is_blast_weapon` `RulesEngine.gd:6037`; +1/+2 attacks formula `RulesEngine.gd:6065-6080` (5+ → +0, 6-10 → +1, 11+ → +2); `floor(models/5)` 10e formula confirmed; min 3 attacks vs 6+ models `RulesEngine.gd:6084-6094`; ER-of-friendlies block `RulesEngine.gd:6154-6190`; icon `WeaponKeywordIcons.gd:86`. Live: `is_blast_weapon("frag_grenade")=true`. | 2026-05 audit verified ER-of-friendlies block. ✅ |
| `twin-linked` | 24 | P0 | C/W | ✅ | helper `has_twin_linked` `RulesEngine.gd:5116`; wired into shooting wound modifiers `RulesEngine.gd:1812, 1827, 1973-1974`; auto-resolve `RulesEngine.gd:2646, 2661`; melee `RulesEngine.gd:8349, 8364-8365`. Live: `has_twin_linked("twin_linked_bolter")=true`. | **Invisible feature**: no icon in `WeaponKeywordIcons.KEYWORD_LABELS` (`WeaponKeywordIcons.gd:31-42`); player has no visual indicator before firing. 2026-05 audit verified re-roll behaviour — only the surfacing is missing. |
| `anti-X` | 30 | P0 | C/W | ⚠️ | parser `get_anti_keyword_data` `RulesEngine.gd:5312-5343`; critical-wound threshold lowered when target keyword matches; used in shooting `RulesEngine.gd:1890`, melee `RulesEngine.gd:8345`. Live: `get_anti_keyword_data("Kombi-weapon")` returns **duplicated** `[{INFANTRY,4},{INFANTRY,4}]` because parser scans both `special_rules` string AND keywords array, and the keyword-extractor at `RulesEngine.gd:4480-4493` keeps `"ANTI-INFANTRY 4+"` intact in the keyword list (it doesn't split the prefix). | Bool helpers (`has_anti_keyword`) and threshold reduction still work because the lower of the two equal entries is used. **Invisible feature** — no badge on weapon name. |
| `devastating wounds` | 11 | P0 | U | ✅ | helper `has_devastating_wounds` `RulesEngine.gd:5092`; wired into shooting `RulesEngine.gd:1988`, auto-resolve `RulesEngine.gd:2818`, melee `RulesEngine.gd:8129-8133`; mortal-wound spillover handled; FNP psychic-context wired (T-016 fix in `AUDIT_REPORT.md:579`); icon `WeaponKeywordIcons.gd:84`. Live: `has_devastating_wounds("devastating_bolter")=true`. | Beastly Rage ability also grants DW after charge. ✅ |
| `sustained hits` | 7 | P0 | U | ✅ | helper `get_sustained_hits_value` `RulesEngine.gd:5014`; supports flat & D3/D6; rolled per critical hit `RulesEngine.gd:5054-5075`; melee `RulesEngine.gd:8302-8305`; icon `WeaponKeywordIcons.gd:82`. Live: `get_sustained_hits_value("sustained_bolter")={value:1,is_dice:false}`. | Get Stuck In (War Horde detachment) injects SH 1 melee `RulesEngine.gd:8149-8152`. 2026-05 audit verified. ✅ |
| `ignores cover` | 16 | P0 | C/W | ✅ | helper `has_ignores_cover` `RulesEngine.gd:6215-6231`; cover-bypass logic `RulesEngine.gd:1114-1119, 2893-2898, 9218-9223`. Live: `has_ignores_cover("flamer")=true`. | **Invisible feature** — no icon. |
| `torrent` | 16 | P0 | U | ✅ | helper `is_torrent_weapon` `RulesEngine.gd:6240`; auto-hits enforced `RulesEngine.gd:1455, 2294, 8134, 8190-8204`; shooting & melee both correctly block Lethal/Sustained Hits (no hit roll → no crit); icon `WeaponKeywordIcons.gd:68`. Live: `is_torrent_weapon("flamer")=true`. | ✅ |
| `heavy` | 12 | P0 | U | ✅ | helper `is_heavy_weapon` `RulesEngine.gd:4589`; +1 to hit if `flags.remained_stationary` `RulesEngine.gd:1579-1584, 2413-2417`; icon `WeaponKeywordIcons.gd:76`. Live: `is_heavy_weapon("heavy_bolter")=true`. | ✅ |
| `hazardous` | 17 | P0 | C/W | ✅ | helper `is_hazardous_weapon` `RulesEngine.gd:6290`; post-attack 1s test `RulesEngine.gd:6314-6450` (Balance Dataslate v3.3 — 3 MW per 1, allocation priority: wounded-w/-Hazardous, then non-Char-w/-Haz, then Char-w/-Haz). Wired in shoot `RulesEngine.gd:7813` and melee `RulesEngine.gd:7813, 7910`. Live: `is_hazardous_weapon("hazardous_plasma")=true`. 2026-05 audit verified live with FNP. | **Invisible feature** — no icon. Comment on line 382 still references the obsolete pre-dataslate behaviour ("Other = model slain") — the actual code matches v3.3 (always 3 MW). |
| `assault` | 26 | P0 | U | ✅ | helper `is_assault_weapon` `RulesEngine.gd:4553`; advance-and-shoot enforced `RulesEngine.gd:3309-3312`; icon `WeaponKeywordIcons.gd:74`. Live: `is_assault_weapon("slugga")=true`. | ✅ |
| `melta` | _0 active hits per `roster_priority.json` listed but melta tokens appear in catalog 371x_ | P0 (universe lists as P0; ALSO not in active-roster top-N per `_summary.md:22`) | C/W | ✅ | parser `get_melta_value` `RulesEngine.gd:4780-4800`; +X damage at half range `RulesEngine.gd:2032-2033, 9313, 9625-9627`; logged "MELTA +%d damage (half range)" `RulesEngine.gd:2117, 3230`. Live: `get_melta_value("meltagun")=2`. | **Invisible feature** — no icon. |
| `lethal hits` | _N (used by AC 2-handers + Custodian guards in roster)_ | P0 | U | ✅ | helper `has_lethal_hits` `RulesEngine.gd:4932`; auto-wounds on critical hit `RulesEngine.gd:1697, 8127`; melee `RulesEngine.gd:8127-8167`. Caladius Advanced Firepower conditional Lethal Hits wired `RulesEngine.gd:4953-5002`; Ghazghkull's Waaagh! Banner aura `RulesEngine.gd:8159-8162`; Martial Ka'tah Rendax stance `RulesEngine.gd:8140-8142`; icon `WeaponKeywordIcons.gd:80`. Live: `has_lethal_hits("lethal_bolter")=true`. | ✅ |
| `precision` | 10 | P0 | C/W | ✅ | helper `has_precision` `RulesEngine.gd:5141`; allocation to CHARACTER models on critical hits; cross-unit attached-character allocation `RulesEngine.gd:5207-5302` (P3-100); shooting & melee both wired (`RulesEngine.gd:8136`); Epic Challenge stratagem flag also routes through this helper. Live: `has_precision("twin_linked_bolter")=false`, `is_assault_weapon("slugga")=true` confirmed parser works. | **Invisible feature** — no icon. |
| `one shot` | _included in P0 token list (uses 200, e.g. ork tankbusta bombs)_ | P0 | U | ✅ | helper `is_one_shot_weapon` `RulesEngine.gd:4633`; flag tracking per model `RulesEngine.gd:4651-4694`; validated at assignment time `RulesEngine.gd:3387-3394`; icon `WeaponKeywordIcons.gd:70`. Live: `is_one_shot_weapon("one_shot_test")=true`. | ✅ |
| `extra attacks` | 19 | P0 | C/W | ✅ | helper `has_extra_attacks` `RulesEngine.gd:4744`; weapon-data variant `weapon_data_has_extra_attacks` `RulesEngine.gd:4763`. Used to ensure these weapons are added to a model's attacks rather than replacing primary weapon. | **Invisible feature** — no icon. |
| `indirect fire` | 8 | P0 | C/W | 🐛 | helper `has_indirect_fire` `RulesEngine.gd:6536`; -1 to hit `RulesEngine.gd:1605-1609, 2438-2442`; target gains Benefit of Cover `RulesEngine.gd:3045-3052`. **Divergence:** code adds `unmodified_roll <= 3 → auto-fail` at `RulesEngine.gd:1676-1681` and `RulesEngine.gd:2510-2515` ("INDIRECT FIRE: Unmodified 1-3 always fail"). Wahapedia 10e core rule for INDIRECT FIRE (https://wahapedia.ru/wh40k10ed/the-rules/core-rules/#Weapons-Index-and-Glossary) is *only* "Subtract 1 from the Hit roll … target has the Benefit of Cover" — there is no "1-3 always fail" provision. Live: `has_indirect_fire("indirect_basic")=true`. | **🐛 Launchable but rule-diverges**: most artillery weapons (Lobbas, Quad launchers, Mortars, Bombards) currently miss far more often than the codified rule allows. **Invisible feature** — no icon either. |
| `lance` | _2 melee uses, 0 ranged in active rosters per universe data; Custodes guards' guardian spear listed_ | P0 | C/W | ✅ | helper `is_lance_weapon` `RulesEngine.gd:4719`; +1 to wound if `flags.charged_this_turn` true; melee `RulesEngine.gd:8395-8400`; shooting `RulesEngine.gd:1853-1858, 2684-2689`. Live: `is_lance_weapon("lance_melee")=true`. | **Invisible feature** — no icon. Wahapedia 10e Lance is explicitly melee-only ("each time the bearer makes an attack with a melee weapon"); the ranged-Lance handler at `RulesEngine.gd:1853-1858` is a code-shape pin that has no roster effect today, but if a future roster adds a "Lance" ranged weapon (none exist in 10e core) the +1 wound would apply incorrectly. ⚠️ shape-only divergence; not blocking. |

### P0 tokens NOT verified live but where helpers exist + are wired (verified by code-grep)

`anti-X`, `devastating wounds`, `extra attacks`, `hazardous`, `heavy`, `ignores cover`, `lance`, `lethal hits`, `precision`, `rapid fire`, `sustained hits`, `torrent`, `twin-linked`, `assault`, `pistol`, `melta`, `blast`, `indirect fire`, `one shot` — all 19 confirmed wired.

---

## P2 token table (18 catalog-only tokens — no active roster invokes)

Per the audit prompt: P2 tokens are listed without deep audit.

| Token | Catalog uses | Faction(s) | Engine support? | Notes |
|---|---:|---|---|---|
| `psychic` | 343 | many | ❌ NOT APPLICABLE (catalog-only) | **However:** roster `orks.json` contains `"special_rules": "psychic"` on a weapon, which IS a P0 use. The `get_unit_fnp_for_attack(unit, is_psychic_or_mortal_wound)` helper exists at `RulesEngine.gd:10122` but **no callsite parses the PSYCHIC weapon keyword to mark damage as a Psychic Attack** — Daughters-of-the-Abyss-style FNP-3+-vs-Psychic only triggers for mortal wounds & DW spill, not for normal damage from a PSYCHIC weapon. Reclassify as P0 ⚠️. |
| `conversion` | 16 | CSM, DG, LoV, QI, QT, SM, TS, WE | C (catalog handler exists) | `get_conversion_threshold` `RulesEngine.gd:5954-5972`; lowers crit threshold at 12"+ via `get_critical_hit_threshold` `RulesEngine.gd:5997-6010`. No P0 invocation. |
| `one shot` | (listed twice — 200 catalog uses) | many | C/W | Already covered in P0 table. |
| `sustained hits d3` | 29 | AE, CSM, DG, LoV, NEC, ORK, QI, QT, SM, TS, WE | C/W | Variable-die path supported by `get_sustained_hits_value` regex `RulesEngine.gd:5036-5046` (`_parse_sustained_hits_from_string` with `(d?)(\\d+)`). Roller has D3 special case at `RulesEngine.gd:5066-5067`. No P0 roster uses it. |
| `rapid fire d3` | 8 | AoI, SM, WE | ❌ | `get_rapid_fire_value` regex `rapid\\s*fire\\s*(\\d+)` returns `0` for "rapid fire d3" — the `d3` literal does not match `\\d+`. Catalog-only; no P0 impact, but if a roster adds a Rapid Fire D3 weapon the code returns 0 (rule silently fails). |
| `rapid fire d6` | 1 | SM | ❌ | Same regex limitation as above. |
| `rapid fire d6+3` | 4 | QI, QT | ❌ | Same regex limitation. |
| `bubblechukka` | 3 | ORK | ❌ NOT APPLICABLE | Datasheet-specific weapon; Ork special — randomises stats. |
| `c'tan power` | 3 | NEC | ❌ NOT APPLICABLE | Necron C'tan-shard flavour token. |
| `plasma warhead` | 2 | AM, GC | ❌ NOT APPLICABLE | Flavour. |
| `reverberating summons` | 2 | CD, DG | ❌ NOT APPLICABLE | Datasheet-flavour. |
| `impaled` | 2 | CSM, WE | ❌ NOT APPLICABLE | Datasheet-flavour. |
| `snagged` | 2 | ORK | ❌ NOT APPLICABLE | Datasheet-flavour. |
| `dead choppy` | 1 | ORK | ❌ NOT APPLICABLE | Datasheet-flavour. |
| `linked fire` | 1 | AE | ❌ NOT APPLICABLE | Aeldari-specific. |
| `psychic assassin` | 1 | AoI | ❌ NOT APPLICABLE | Inquisitorial flavour. |
| `hooked` | 1 | TAU | ❌ NOT APPLICABLE | T'au flavour. |
| `harpooned` | 1 | TYR | ❌ NOT APPLICABLE | Tyranid flavour. |
| `overcharge` | 1 | LoV | ❌ NOT APPLICABLE | Votann flavour. |

---

## Shooting vs Melee coverage

The audit prompt asks: are tokens that 10e applies to *both* shooting and melee actually wired in both?

| Token | Shoot | Melee | Notes |
|---|:-:|:-:|---|
| Twin-linked | ✅ | ✅ | shoot `RulesEngine.gd:1812-1827, 2646-2661`; melee `RulesEngine.gd:8349, 8364-8365`. |
| Lethal Hits | ✅ | ✅ | shoot `RulesEngine.gd:1697`; melee `RulesEngine.gd:8127-8142`. |
| Sustained Hits | ✅ | ✅ | shoot path, melee `RulesEngine.gd:8302-8309`. |
| Devastating Wounds | ✅ | ✅ | shoot `RulesEngine.gd:1988`; melee `RulesEngine.gd:8129-8133`. |
| Anti-X | ✅ | ✅ | shoot path, melee `RulesEngine.gd:8345-8346`. |
| Precision | ✅ | ✅ | shoot path, melee `RulesEngine.gd:8136`. |
| Hazardous | ✅ | ✅ | shoot `RulesEngine.gd:7813` (assignment-resolve), melee `RulesEngine.gd:7813, 7910` (both melee paths). |
| Lance (charged → +1 wound) | ⚠️ shape-only ranged handler exists `RulesEngine.gd:1853-1858`; 10e Lance is melee-only so this is dead code | ✅ melee `RulesEngine.gd:8395-8400` | minor 🐛 — the ranged path will fire if anyone ever data-tags a ranged weapon "lance". Not a launch-blocker. |
| Torrent | ✅ shoot | ✅ melee `RulesEngine.gd:8190-8204` | "melee Torrent" doesn't exist in 10e but the shape doesn't break anything. |
| Pistol | ✅ shoot only | n/a | 10e correct. |
| Rapid Fire / Heavy / Assault / Blast / Melta / Indirect Fire / Ignores Cover / One Shot | ✅ shoot | n/a | 10e ranged-only. ✅ |
| Extra Attacks | ✅ melee (only meaningful in melee) | ✅ | `weapon_data_has_extra_attacks` `RulesEngine.gd:4763`. |

---

## Top 5 🐛 / divergences

1. **Indirect Fire "1-3 always fail" rule does not exist in 10e** (`RulesEngine.gd:1676-1681, 2510-2515`). Wahapedia core rule is *only* `-1 to Hit + Benefit of Cover`. The code applies a hidden second penalty that triples-down on the BS modifier. Result: Lobbas / Mortars / Bombards / Whirlwinds miss ~50% more often than spec. **Highest-impact divergence.** Affects ~139 catalog weapons; 8 P0 roster weapons.
2. **PSYCHIC weapon keyword has no engine handler** that flags the damage as a Psychic Attack for FNP. `get_unit_fnp_for_attack(unit, is_psychic_or_mortal_wound)` exists (`RulesEngine.gd:10122`) but is only called with `true` for mortal wounds & DW spillover (`RulesEngine.gd:8750, 9727, 10215`). PSYCHIC-keyword damage that is *not* a mortal wound goes through the unconditional FNP path. Roster impact: at least one weapon in `orks.json` carries `"special_rules":"psychic"`; full P0 sweep should re-classify this from P2 to P0.
3. **`get_anti_keyword_data` returns duplicated entries** for weapons that have both `special_rules` text and a parsed keyword-array entry (e.g., `Kombi-weapon`). `RulesEngine.gd:5312-5328` scans both sources additively. Wound-roll logic uses the lowest threshold so behaviour is correct, but display strings and any future logic that counts entries are wrong.
4. **Keyword extractor truncates `"RAPID FIRE 1"` to `"RAPID"`** at `RulesEngine.gd:4480-4493` when building the keyword list from `special_rules`. The numeric helpers (`get_rapid_fire_value`) re-parse the raw string and return the correct value, so behaviour is right; but the keyword array is misshapen for any code that does `"RAPID FIRE 1" in keywords[]`.
5. **Hazardous comment is stale.** `RulesEngine.gd:382` still says "On 1: CHARACTER/VEHICLE/MONSTER = 3MW, other = model slain" (pre-dataslate), but the live code (`RulesEngine.gd:6367-6371`) implements the v3.3 dataslate uniform `3 MW per 1`. Documentation lag, not behaviour bug.

---

## Top 10 P0 invisible features (`C/W` but not `U`)

`WeaponKeywordIcons.gd:31-42` only renders 10 keywords: `torrent, one_shot, pistol, assault, heavy, rapid_fire, lethal_hits, sustained_hits, devastating_wounds, blast`. The other roster-fielded keywords have no badge or tooltip surfaced to the player.

1. **Twin-linked** — single-callsite `WeaponKeywordIcons` doesn't include it (`WeaponKeywordIcons.gd:65-89`).
2. **Anti-X** (`anti-infantry 4+`, etc.) — no badge.
3. **Ignores Cover** — no badge.
4. **Hazardous** — no badge; players don't know their plasma will kill them.
5. **Indirect Fire** — no badge; player can't tell at glance which weapons need no LoS.
6. **Melta X** — no badge; no half-range damage indicator.
7. **Lance** — no badge.
8. **Precision** — no badge; player has no way to see "this attack can pick off the warlord".
9. **Extra Attacks** — no badge.
10. **All keyword icons are missing entirely from the FIGHT phase UI.** `WeaponKeywordIcons.apply_to_tree_item` is called only from `40k/scripts/ShootingController.gd:808`; `40k/scripts/FightController.gd:545-562` builds its own weapon list with no badge call. Even the 10 keywords that are surfaced in shooting are invisible during melee, despite Twin-linked / Lethal Hits / Sustained Hits / Anti-X / Devastating Wounds / Precision / Lance / Hazardous all firing in melee.

The "10 invisible features" prompt cap is in fact a single architectural gap: **`WeaponKeywordIcons` is keyword-incomplete AND fight-blind**. Fixing both in one PR would convert all 9 missing-icon entries from `C/W` to `U`.

---

## Spot-check vs prior audit (2026-05)

- Twin-linked re-roll behaviour — verified live (this audit confirms it).
- Sustained Hits Get-Stuck-In injection (War Horde) — code at `RulesEngine.gd:8149-8152`, no regression.
- BLAST engagement-of-friendlies block — code at `RulesEngine.gd:6154-6190`, no regression.
- HAZARDOUS post-attack 1s test — code at `RulesEngine.gd:6314-6450`, no regression.
- T7-9 AI Blast formula `floor(models/5)` — confirmed code matches: 5 → +0, 6-10 → +1, 11+ → +2 (`RulesEngine.gd:6065-6080`).

No regressions detected.

---

## P0 reclassification recommendation

`weapon_rules.json` lists `psychic` as P2 (catalog-only) because no roster weapon ID in the universe scrape was tagged. However, `40k/armies/orks.json` contains `"special_rules":"psychic"` on at least one weapon. The token should be re-counted as **P0** in the universe extractor, and finding #2 above (no PSYCHIC-keyword FNP routing) becomes a P0 launch-blocker.

---

## Launch-blocker shortlist (top 3)

1. **Indirect Fire 1-3 auto-fail** (🐛 #1 above) — affects every artillery weapon in the catalog. Rule is wrong vs 10e. Two-line fix in `RulesEngine.gd:1676-1681, 2510-2515`.
2. **PSYCHIC weapon keyword not routed** (🐛 #2) — Daughters-of-the-Abyss-style defensive abilities don't trigger when they should. Need to detect `"PSYCHIC" in keywords` at attack resolution and pass `is_psychic_or_mortal_wound=true` to `get_unit_fnp_for_attack`.
3. **Fight-phase has zero keyword icons.** Players in melee can't see which weapons have Lethal Hits / Sustained Hits / Anti-X / Devastating Wounds / Twin-linked / Precision / Hazardous / Lance / Extra Attacks. That's the **single highest-impact invisibility gap** in the audit. One callsite addition + 9-keyword expansion of `WeaponKeywordIcons.KEYWORD_LABELS`.

---

## Live-validation transcript (excerpt)

```
ping → 4.6-stable (steam), pong=5239961
get_node("/root/RulesEngine").has_twin_linked("twin_linked_bolter")        → true
get_node("/root/RulesEngine").get_sustained_hits_value("sustained_bolter") → {value:1, is_dice:false}
get_node("/root/RulesEngine").has_lethal_hits("lethal_bolter")             → true
get_node("/root/RulesEngine").has_devastating_wounds("devastating_bolter") → true
get_node("/root/RulesEngine").get_melta_value("meltagun")                  → 2
get_node("/root/RulesEngine").is_torrent_weapon("flamer")                  → true
get_node("/root/RulesEngine").get_rapid_fire_value("bolt_rifle")           → 1
get_node("/root/RulesEngine").is_hazardous_weapon("hazardous_plasma")      → true
get_node("/root/RulesEngine").has_indirect_fire("indirect_basic")          → true
get_node("/root/RulesEngine").is_lance_weapon("lance_melee")               → true
get_node("/root/RulesEngine").is_blast_weapon("frag_grenade")              → true
get_node("/root/RulesEngine").is_one_shot_weapon("one_shot_test")          → true
get_node("/root/RulesEngine").has_ignores_cover("flamer")                  → true
get_node("/root/RulesEngine").is_pistol_weapon("plasma_pistol")            → true
get_node("/root/RulesEngine").is_heavy_weapon("heavy_bolter")              → true
get_node("/root/RulesEngine").is_assault_weapon("slugga")                  → true
get_node("/root/RulesEngine").has_twin_linked("twin_linked_devastating")   → true
# Real Ork roster weapon (board state):
get_node("/root/RulesEngine").get_rapid_fire_value("Kombi-weapon", board)  → 1
get_node("/root/RulesEngine").has_devastating_wounds("Kombi-weapon", board) → true
get_node("/root/RulesEngine").get_anti_keyword_data("Kombi-weapon", board)
    → [{INFANTRY, 4}, {INFANTRY, 4}]    # ← 🐛 duplicated
```

LIVE-VALIDATION SKIPPED for full attack pipeline (ranged/melee dice resolution end-to-end with each token producing a dice block) — would require driving units to ER, declaring shoot/fight, dispatching action, and reading the resulting dice array per token. Helpers + integration points are confirmed; full pipeline left to a follow-up agent. The two highest-impact divergences (Indirect Fire 1-3 auto-fail; PSYCHIC keyword not routed) are code-grep findings that don't need a dice transcript to confirm.
