#!/usr/bin/env python3
"""How good is the in-game forecast? Score it against real outcomes.

AIDecisionMaker records one rest-of-battle forecast per own turn (decision
type "forecast", FORECAST_LOG = 1; AIForecast.gd, the GDScript port of the
Combat Calc forecast). This tool joins those predictions with each game's
final score and reports, per battle round:

  * Brier score of the forecast win chance, against a coin flip (0.25);
  * RMSE / correlation of the forecast final margin (my VP - theirs) vs the
    real final margin, against the naive "current VP difference";
  * a least-squares calibration  real = a + b * forecast + c * first_player
    (first_player = +1 for the player who took the first turn, -1 otherwise),
    which the AI reads as FORECAST_CAL_A / _B / _SEAT (see FORECAST_TEMPO).

Usage:
    python3 tools/ai_lab/forecast_calibration.py SEASON_DIR [SEASON_DIR ...] [--json OUT]
    python3 tools/ai_lab/forecast_calibration.py --selftest
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from build_index import find_records, load_record  # noqa: E402


def final_totals(rec: dict) -> dict | None:
    out = rec.get("outcome") or {}
    if str(out.get("status", "")) not in ("completed", "complete", "game_over"):
        return None
    if int(out.get("battle_round", 0) or 0) < 5:
        return None
    vp = out.get("vp") or {}
    try:
        return {1: float(vp["player1"]["total"]), 2: float(vp["player2"]["total"])}
    except (KeyError, TypeError, ValueError):
        return None


def extract(rec: dict) -> list[dict]:
    """One row per recorded forecast: player, round, first, prediction, outcome."""
    final = final_totals(rec)
    if final is None:
        return []
    rows: list[dict] = []
    first = None
    for batch in rec.get("decisions") or []:
        for r in batch.get("records") or []:
            if r.get("decision_type") != "forecast":
                continue
            cands = r.get("candidates") or []
            if not cands:
                continue
            sb = cands[0].get("score_breakdown") or {}
            player = int(batch.get("player", 0) or 0)
            rnd = int(batch.get("round", 0) or 0)
            if first is None and rnd == 1:
                first = player  # the first forecast of round 1 is the first player's
            opp = 2 if player == 1 else 1
            real = final[player] - final[opp]
            rows.append({
                "game": rec.get("game_id", ""), "player": player, "round": rnd,
                "p_win": float(sb.get("p_win", 0.5)), "margin": float(sb.get("margin", 0.0)),
                "now": float(sb.get("vp_me", 0.0)) - float(sb.get("vp_opp", 0.0)),
                "real": real, "won": 1.0 if real > 0 else (0.5 if real == 0 else 0.0),
            })
    for row in rows:
        row["first"] = 1.0 if row["player"] == (first or 1) else -1.0
    return rows


def lstsq(xs: list[list[float]], ys: list[float]) -> list[float]:
    """Ordinary least squares via the normal equations (tiny k, no numpy)."""
    k = len(xs[0])
    a = [[sum(x[i] * x[j] for x in xs) for j in range(k)] for i in range(k)]
    b = [sum(x[i] * y for x, y in zip(xs, ys)) for i in range(k)]
    for c in range(k):  # Gauss-Jordan with partial pivoting
        p = max(range(c, k), key=lambda r: abs(a[r][c]))
        a[c], a[p], b[c], b[p] = a[p], a[c], b[p], b[c]
        if abs(a[c][c]) < 1e-12:
            return [0.0] * k
        for r in range(k):
            if r != c:
                f = a[r][c] / a[c][c]
                a[r] = [v - f * w for v, w in zip(a[r], a[c])]
                b[r] -= f * b[c]
    return [b[i] / a[i][i] for i in range(k)]


def corr(xs: list[float], ys: list[float]) -> float:
    n = len(xs)
    if n < 3:
        return float("nan")
    mx, my = sum(xs) / n, sum(ys) / n
    sx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    sy = math.sqrt(sum((y - my) ** 2 for y in ys))
    if sx == 0 or sy == 0:
        return float("nan")
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / (sx * sy)


def rmse(pred: list[float], ys: list[float]) -> float:
    return math.sqrt(sum((p - y) ** 2 for p, y in zip(pred, ys)) / max(1, len(ys)))


def summarise(rows: list[dict]) -> dict:
    out: dict = {"rows": len(rows), "games": len({r["game"] for r in rows}), "by_round": {}}
    if not rows:
        return out
    groups = {"all": rows}
    for rnd in sorted({r["round"] for r in rows}):
        groups["R%d" % rnd] = [r for r in rows if r["round"] == rnd]
    for name, g in groups.items():
        ys = [r["real"] for r in g]
        coef = lstsq([[1.0, r["margin"], r["first"]] for r in g], ys) if len(g) >= 4 else [0.0, 0.0, 0.0]
        cal = [coef[0] + coef[1] * r["margin"] + coef[2] * r["first"] for r in g]
        now_coef = lstsq([[1.0, r["now"], r["first"]] for r in g], ys) if len(g) >= 4 else [0.0, 0.0, 0.0]
        now_cal = [now_coef[0] + now_coef[1] * r["now"] + now_coef[2] * r["first"] for r in g]
        out["by_round"][name] = {
            "n": len(g),
            "brier_forecast": sum((r["p_win"] - r["won"]) ** 2 for r in g) / len(g),
            "brier_coin": sum((0.5 - r["won"]) ** 2 for r in g) / len(g),
            "rmse_forecast_raw": rmse([r["margin"] for r in g], ys),
            "rmse_now_raw": rmse([r["now"] for r in g], ys),
            "rmse_forecast_cal": rmse(cal, ys),
            "rmse_now_cal": rmse(now_cal, ys),
            "corr_forecast": corr([r["margin"] for r in g], ys),
            "corr_now": corr([r["now"] for r in g], ys),
            "cal": {"a": coef[0], "b": coef[1], "seat": coef[2]},
            "cal_now": {"a": now_coef[0], "b": now_coef[1], "seat": now_coef[2]},
            "mean_bias_forecast": sum(r["margin"] - r["real"] for r in g) / len(g),
        }
    return out


def report(s: dict) -> str:
    lines = ["forecast calibration: %d predictions from %d completed games" % (s["rows"], s["games"])]
    if not s["rows"]:
        return lines[0] + " (no forecast records: was FORECAST_LOG on?)"
    lines.append("%-4s %4s  %-13s %-23s %-23s %-11s %s" % ("", "n", "Brier fc/coin", "RMSE raw fc/now",
                                                          "RMSE calibrated fc/now", "corr fc/now", "cal a + b*fc + seat"))
    for name, r in s["by_round"].items():
        lines.append("%-4s %4d  %.3f/%.3f   %6.1f/%6.1f            %6.1f/%6.1f            %+.2f/%+.2f  %+.1f %+.2f %+.1f" % (
            name, r["n"], r["brier_forecast"], r["brier_coin"], r["rmse_forecast_raw"], r["rmse_now_raw"],
            r["rmse_forecast_cal"], r["rmse_now_cal"], r["corr_forecast"], r["corr_now"],
            r["cal"]["a"], r["cal"]["b"], r["cal"]["seat"]))
    return "\n".join(lines)


def selftest() -> int:
    import random
    rnd = random.Random(3)
    recs = []
    for g in range(40):
        skill = rnd.gauss(0, 12)  # true final margin for P1
        dec = []
        for r in range(1, 6):
            for p in (1, 2):
                sign = 1 if p == 1 else -1
                noise = rnd.gauss(0, 14 / r)
                m = sign * skill + noise
                dec.append({"player": p, "round": r, "records": [{"decision_type": "forecast", "candidates": [
                    {"score_breakdown": {"p_win": 1 / (1 + math.exp(-m / 8)), "margin": m, "vp_me": 0, "vp_opp": 0}}]}]})
        tot1 = 80 + skill / 2
        recs.append({"game_id": "g%d" % g, "decisions": dec, "outcome": {"status": "completed", "battle_round": 5,
                     "vp": {"player1": {"total": tot1}, "player2": {"total": tot1 - skill}}}})
    rows = [row for rec in recs for row in extract(rec)]
    s = summarise(rows)
    ok = True
    ok &= s["games"] == 40 and s["rows"] == 400
    a = s["by_round"]["all"]
    ok &= a["brier_forecast"] < a["brier_coin"]
    ok &= a["corr_forecast"] > 0.6
    ok &= abs(s["by_round"]["R5"]["cal"]["b"] - 1.0) < 0.25
    ok &= s["by_round"]["R5"]["rmse_forecast_raw"] < s["by_round"]["R1"]["rmse_forecast_raw"]
    print(report(s))
    print("selftest", "PASS" if ok else "FAIL")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("seasons", nargs="*")
    ap.add_argument("--json", default="")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    rows = []
    for d in a.seasons:
        for path in find_records(d):
            try:
                rows.extend(extract(load_record(path)))
            except (OSError, ValueError) as e:
                print("skip %s: %s" % (path, e), file=sys.stderr)
    s = summarise(rows)
    print(report(s))
    if a.json:
        with open(a.json, "w") as f:
            json.dump(s, f, indent=1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
