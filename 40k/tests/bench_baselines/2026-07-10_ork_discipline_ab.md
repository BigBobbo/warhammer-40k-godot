# Ork discipline A/B — 2026-07-10

**Diagnosis being tested** (from the soak post-mortem): the Orks lose with
their army alive. 7–11 of ~14 units "chase enemy" every round (45"+ chases in
round 1) because `FACTION_AGGRESSION_ORKS = 1.8` crosses the ≥1.5 gate that
turns every melee-capable unit — including shooty ones like Lootas, Kaptin
Badrukk and the Battlewagon — into an enemy-seeker that bypasses its
objective assignment. Primary VP starves: ≈6 per game vs P1's 21–36.

**Arms** (P2-only profiles, standard fixture, P1 first, Hard, seeds 2001–2010):
- **Arm A** `orks_discipline_a.json`: `FACTION_AGGRESSION_ORKS: 1.2` — below
  the seeker gate; genuinely melee-focused units (Boyz, Warbosses) still seek.
- **Arm B** `orks_discipline_b.json`: Arm A + objective pull
  (`WEIGHT_SCORING_URGENCY 5.0`, `URGENCY_ROUND_2_CONTEST 3.5`,
  `WEIGHT_UNCONTROLLED_OBJ 13.0`).

## Results (avg VP diff P2−P1, Hard)

| Config | Avg margin | Outcomes | P2 primary/game (avg) |
|---|---|---|---|
| Baseline (aggression 1.8) | **−28.3** | 10 losses | ≈ 6 |
| Arm A (1.2) | **−15.1** | 9 losses, 1 draw | ≈ 21 |
| Arm B (1.2 + objective pull) | **−13.6** | 9 losses, **1 win** | ≈ 22 |

Per-game margins:

| seed | Arm A | Arm B |
|---|---|---|
| 2001 | −10 | −10 |
| 2002 | −14 | −24 |
| 2003 | −34 | −24 |
| 2004 | −18 | −5 |
| 2005 | −14 | **+3 (P2 win)** |
| 2006 | −20 | −15 |
| 2007 | −15 | −22 |
| 2008 | −13 | −18 |
| 2009 | −13 | −7 |
| 2010 | **0 (draw)** | −14 |

Zero stalls in all 40 experiment games (60 games total since the SOAK fixes).

## Conclusions

1. **The chase diagnosis is confirmed causally.** One parameter change more
   than triples Ork primary VP (6 → ~21/game) and halves the loss margin
   (−28.3 → −15.1). Adding objective pull (Arm B) is marginally better
   (−13.6) and produced the first Ork win under normal turn order; A vs B is
   within noise, but both are decisively better than baseline (~14 VP ≈ >3
   standard errors on 10 games).
2. Combined with the first-turn finding (~19 VP at Hard), disciplined Orks
   going first would be roughly at parity in this matchup — the "P1 always
   wins" sweep is fully accounted for by (a) chase behavior and (b) turn
   order, not by shooting/fight quality.
3. **Default change shipped with this report:** `FACTION_AGGRESSION_ORKS`
   1.8 → 1.2 (the exact tested value). World Eaters / Khorne / Custodes
   values are untouched (untested).
4. **Better long-term fix (roadmap):** the mechanism, not the number — the
   melee-seek gate should never capture ranged-focused units (it already
   excludes ranged VEHICLES but not ranged infantry/characters), and
   move-assigned units need the same chase-distance caps hold-assigned units
   already have. That would let flavor-level aggression stay high without
   sacrificing the objective game.

## Method notes

- Seeds fix dice + secondary decks, but trajectories vary with wall-clock
  timing — per-seed pairs are indicative, aggregates are the metric.
- Profiles live in `tests/bench_profiles/` and are reusable:
  `bash 40k/tests/run_ai_benchmark.sh 10 audit_baseline_postdeploy "" res://tests/bench_profiles/orks_discipline_b.json`
