#!/usr/bin/env python3
"""Run a named batch of themed regexes over the corpus in one pass.

Batches are declared in BATCHES below so a scan is reproducible and reviewable:
each theme is a decision the AI has to make, and the regex is the phrasing
players use when they talk about making it.

    python3 batch.py general_a [--max 8] [--width 190]
"""

from __future__ import annotations

import argparse
import sys

from search_transcripts import load
from mine import run

BATCHES = {
    "positioning": [
        ("OVERWATCH-move-cost", r"(before|worry|scared|afraid|because) .{0,30}overwatch|overwatch .{0,25}(punish|tax|threat|deterrent)"),
        ("STAGING-out-of-los", r"stag(e|ing).{0,40}(out of|behind|hidden|los|line of sight)|out of (line of sight|los).{0,30}stag"),
        ("OBSCURING-play", r"obscur\w+.{0,60}(so|because|means|can'?t see)"),
        ("MOVE-BLOCK", r"(block|blocking).{0,30}(charge|the charge|movement|lane|path)"),
    ],
    "objectives": [
        ("HOLD-vs-PUSH", r"(don'?t|do not) (need to |have to )?(push|overextend|over.commit)|overextend\w*"),
        ("STICKY", r"sticky.{0,80}"),
        ("OC-battleshock", r"battle.?shock\w*.{0,60}(o\.?c\.?|objective|control|score|scoring)"),
        ("SECURE-then-leave", r"(score|secure|hold) (it|the objective).{0,30}(then|and) (leave|move off|walk off)"),
    ],
    "targeting": [
        ("KILL-SCREEN-FIRST", r"(kill|clear|remove|shoot).{0,25}(the )?(screen|screens|chaff|gret?ch?in|grots)"),
        ("PRIORITY-TARGET", r"(priority|primary) target|target priority"),
        ("DONT-OVERKILL", r"overkill|waste (the|those|my) (shots|shooting|attacks)"),
        ("KILL-THE-SCORER", r"kill.{0,30}(what'?s|the unit|things) (on|holding).{0,15}objective"),
    ],
    "commit": [
        ("TURN-TO-COMMIT", r"(turn|round) (two|2|three|3).{0,40}(commit|push|go for it|alpha|strike)"),
        ("PATIENCE", r"(be |stay |play )?patient|don'?t (rush|over.?commit)|wait (a turn|until|for)"),
        ("GO-FIRST-SECOND", r"(want|prefer|choose|rather) (to )?(go|going) (first|second)"),
        ("DOUBLE-DIP", r"(score|scoring) (on|in) (both|two) (turns|rounds)"),
    ],
    "combat": [
        ("FALLBACK-DECIDE", r"fall(ing)? back.{0,60}(because|so|instead|rather|to )"),
        ("STAY-IN-COMBAT", r"(stay|stuck|keep).{0,20}(in|locked in) (combat|melee|engagement)|tie (them|it|him) up"),
        ("CONSOLIDATE-INTO", r"consolidat\w+.{0,60}(onto|into|objective|another unit)"),
        ("CHARGE-TO-LOCK", r"charge.{0,40}(to (tie|lock|stop|shut)|so (they|he) can'?t shoot)"),
    ],
    "abilities": [
        ("WAAAGH-TIMING", r"waaa+gh.{0,80}(turn|round|when|timing|save|hold)"),
        ("OATH-TIMING", r"oath of moment.{0,70}"),
        ("CP-SPEND", r"(save|saving|spend|spending) (my |your |the )?c\.?p\.?|command points? (for|on)"),
        ("ONCE-PER-BATTLE", r"once per (battle|game).{0,60}(save|wait|hold|timing|use it)"),
    ],
    "screening": [
        ("SCREEN-SPACING", r"(spac|space|gap|inch).{0,40}(between|apart).{0,40}(model|unit|screen)"),
        ("SIX-INCH-DS", r"6.?(in|inch|\")? deep ?strike|six inch deep ?strike"),
        ("SCREEN-COST", r"screen.{0,60}(cost|worth|cheap|expensive|points)"),
        ("RAPID-INGRESS", r"rapid ingress"),
    ],
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("batch", choices=sorted(BATCHES))
    ap.add_argument("--max", type=int, default=8)
    ap.add_argument("--width", type=int, default=190)
    ap.add_argument("--per-video", type=int, default=1)
    args = ap.parse_args()

    recs = list(load())
    for theme, rx in BATCHES[args.batch]:
        hits = run(rx, recs, args.width, args.per_video, args.max)
        print("### %s (%d)" % (theme, len(hits)))
        for h in hits:
            print("- [%s|%s|%s|%s] %s" % (h["channel"][:22], h["date"][5:], h["ts"],
                                          h["video_id"], h["snip"]))
        print()


if __name__ == "__main__":
    main()
