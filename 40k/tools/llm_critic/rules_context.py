"""Rules context for the LLM critic: the 11th edition primer and the acting
player's primary-mission scoring, worked out from their actual card.

The primary table answers "what does one more objective add?": Command-phase
primary VP for holding the home objective (or not) plus 0-4 non-home
objectives, with the engine's 15 VP per-turn cap applied
(MissionManager: 15/turn, 45/game). Awards it cannot resolve from objective
counts alone (majority, central, enemy territory) are listed as notes.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", ".."))
CARDS_PATH = os.path.join(PROJECT, "data", "40kdc", "missionCards.json")
RULES_TEXT = os.path.abspath(os.path.join(PROJECT, "..", "docs", "rules", "40k_11th_edition_core_rules.txt"))
TURN_CAP = 15
GAME_CAP = 45

_cards = None


def primer():
    with open(os.path.join(HERE, "rules_primer.md")) as f:
        return f.read()


def card(card_id):
    global _cards
    if _cards is None:
        with open(CARDS_PATH) as f:
            _cards = {c["id"]: c for c in json.load(f)}
    return _cards.get(card_id, {})


def _command_awards(c):
    return [a for a in c.get("awards", [])
            if a.get("trigger", {}).get("phase") == "command"]


def _award_vp(a, home, n, notes):
    """VP this Command-phase award pays when the player holds their home
    objective (bool) and n non-home objectives; None if it depends on
    something other than counts (then a note explains it)."""
    when = a.get("when", {}) or {}
    wtype = when.get("type", "")
    params = when.get("parameters", {}) or {}
    held = n + (1 if home else 0)
    if "vp_per" in a:
        per = a.get("per", "")
        if wtype == "controls-objective" and params.get("objective") == "your-home" and not home:
            return 0
        if per == "controlled-objective":
            return a["vp_per"] * held
        if per == "controlled-non-home-objective":
            return a["vp_per"] * n
        notes.add(f"+{a['vp_per']} VP per {per.replace('-', ' ')} (not in the table)")
        return None
    vp = a.get("vp", 0)
    if wtype == "controls-objective":
        if params.get("objective") == "your-home":
            return vp if home else 0
        if params.get("objective_role") == "central":
            notes.add(f"+{vp} VP for controlling a central objective (not in the table)")
            return None
        k = int(params.get("count_min", 1))
        count = n if params.get("exclude") == "home" else held
        return vp if count >= k else 0
    if wtype == "objective-majority":
        notes.add(f"+{vp} VP for controlling more objectives than the opponent (not in the table)")
        return None
    notes.add(f"+{vp} VP when {wtype.replace('-', ' ')} (not in the table)")
    return None


def primary_table(card_id):
    """Markdown block describing the card and its capped Command-phase VP by
    objectives held. Empty string when the card is unknown."""
    c = card(card_id)
    if not c:
        return ""
    awards = _command_awards(c)
    notes = set()
    rounds = sorted({json.dumps(a.get("trigger", {}).get("battle_round", {})) for a in awards})
    lines = [f"Primary card: {c.get('name')} ({card_id}). {c.get('text', '')}",
             f"Command-phase primary VP by objectives controlled (capped at {TURN_CAP}/turn; "
             f"{GAME_CAP} primary max per game). Rounds: {', '.join(rounds) or 'n/a'}.",
             "| Home held | 0 non-home | 1 | 2 | 3 | 4 |", "|---|---|---|---|---|---|"]
    for home in (True, False):
        row = []
        for n in range(5):
            total = 0
            for a in awards:
                v = _award_vp(a, home, n, notes)
                total += v or 0
            row.append(str(min(total, TURN_CAP)))
        lines.append(f"| {'yes' if home else 'no'} | " + " | ".join(row) + " |")
    lines.append("Marginal VP of one more non-home objective = the step between adjacent "
                 "cells. Other scoring on this card (end of turn, kills, actions) shares the "
                 f"same {TURN_CAP} VP turn cap.")
    for n in sorted(notes):
        lines.append("- " + n)
    return "\n".join(lines)


if __name__ == "__main__":
    import sys
    for cid in sys.argv[1:] or ["battlefield-dominance", "meatgrinder", "inescapable-dominion"]:
        print(primary_table(cid))
        print()
