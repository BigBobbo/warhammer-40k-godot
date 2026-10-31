# AI lab results, 31 October 2026 (protocol v2)

Copied from the untracked work folder `.ai_lab_work/`.

- `bench_results/aud_*` — arm AUD (V2-4 rules-audit bundle, 11 fixes on, `ca913e2` + `tools/ai_lab/audit_fixes/flip.sh`) vs SHIP `e12e6e8`, looks 1 and 2 (one `BENCH_RESULT` line per shard).
- `decide_v2_AUD_look1.json` — look 1: continue (pooled E +2.53, z 2.36 < 3.710).
- `decide_v2_AUD_look2_manual.json` — look 2: pooled E +2.50, z 3.34 >= 2.512, but the Custodes mirror 95% CI [-5.45, -0.35] is wholly below 0, so no ship. Computed by hand with the registered formula, because `decide_v2.py` skips look 2 when look 1 has 39/40 Ork pairs (one game timed out). Look 3 was not run (paused by the owner).
- `confirmed_h2.txt`, `faded_h2.txt`, `recheck/` — V2-3 horizon-2 re-checks (pr12h2, pr13h2).
- `STATUS.md` — the running lab log.
- `report/` — source of the published report (artifact version 1793460607-4fe6) and its fact sheet.
