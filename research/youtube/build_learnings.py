#!/usr/bin/env python3
"""Single source of truth for the mined findings.

Emits research/youtube/ai_learnings.json (machine-readable, for the LLM that
implements the changes). The HTML page is rendered from that JSON by
build_html.py, so the two can never drift.

Every evidence entry below was produced by search_transcripts.py / mine.py /
faction_mine.py against research/youtube/transcripts_text.jsonl.gz; the
timestamp is the [MM:00] caption marker preceding the quoted line.
"""

from __future__ import annotations

import json
import os
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "ai_learnings.json")

GENERATED = "2026-08-05"

CORPUS = {
    "transcripts": 1029,
    "channels": 90,
    "date_range": "2026-04-04 to 2026-08-04 (68 transcripts carry no date field)",
    "words": 10510642,
    "note": ("Auto-captioned (1027/1029). Heavily skewed to competitive/tournament "
             "content: 414 transcripts tagged Meta, 334 Batreps. 11th edition released "
             "June 2026, so ~92% of the corpus is June-August 2026 and post-dates the "
             "first big balance dataslate (late July 2026)."),
}

DECISIONS = {
    "positioning_and_concealment": (
        "Where a unit physically stands: what it can see, what can see it, what "
        "terrain state it ends its move in, and what that costs or buys."),
    "screening_and_zoning": (
        "Using bodies to deny space — blocking deep strike arrival, blocking charge "
        "lanes, and blocking physical movement paths."),
    "target_selection": (
        "Given a set of legal targets, which one to shoot or fight, and how much to "
        "commit to it."),
    "objective_trade": (
        "Whether to take, hold, contest, or give up an objective, and what that is "
        "worth relative to killing something."),
    "attrition_and_trades": (
        "Whether a unit's likely loss is acceptable for what it buys."),
    "reserves_and_arrival": (
        "What to hold off the table, and when to bring it on."),
    "melee_commitment": (
        "Whether to charge, what to charge, and what a charge is for when it is not "
        "for damage."),
    "disengage_and_lock": (
        "Whether to fall back out of an engagement, or deliberately stay in one to "
        "deny the enemy its shooting."),
    "ability_timing": (
        "When to fire a once-per-battle or once-per-turn army ability, stratagem, or "
        "command resource."),
    "action_economy": (
        "Which unit spends its turn performing a mission action rather than fighting."),
    "tempo_and_commitment": (
        "Which battle round to commit the army, and how much to hold back."),
    "deployment": (
        "Where the army starts, and how that is shaped by what the opponent has put "
        "down."),
}

# Transcript counts from faction_index.py (title match OR >=6 in-body alias hits).
FACTION_TRANSCRIPTS = {
    "general": 1029,
    "Space Marines": 214, "Orks": 213, "Tyranids": 110, "Necrons": 101,
    "Dark Angels": 86, "Death Guard": 79, "Chaos Space Marines": 65,
    "T'au Empire": 65, "Grey Knights": 60, "World Eaters": 58,
    "Blood Angels": 58, "Adeptus Custodes": 54, "Space Wolves": 51,
    "Aeldari": 50, "Thousand Sons": 48, "Leagues of Votann": 47,
    "Drukhari": 46, "Chaos Knights": 43, "Emperor's Children": 43,
    "Genestealer Cults": 34, "Astra Militarum": 32, "Imperial Knights": 32,
    "Adeptus Mechanicus": 31, "Black Templars": 22, "Deathwatch": 18,
    "Chaos Daemons": 15, "Harlequins": 10, "Adepta Sororitas": 9,
    "Agents of the Imperium": 6, "Ynnari": 4,
}


def ev(channel, vid, ts, quote):
    """Evidence row. ts is 'MM:SS'; the deep link seeks to that second."""
    mm, ss = ts.split(":")
    secs = int(mm) * 60 + int(ss)
    return {"channel": channel, "video_id": vid, "timestamp": ts,
            "url": "https://youtube.com/watch?v=%s&t=%ds" % (vid, secs),
            "quote": quote}


F = []


def add(**kw):
    kw["id"] = "F%03d" % (len(F) + 1)
    kw.setdefault("differs_from_general", None)
    kw["corroborating_channels"] = len({e["channel"] for e in kw["evidence"]})
    F.append(kw)


# ---------------------------------------------------------------- positioning
add(
    decision="positioning_and_concealment", faction="general",
    claim="Infantry should end movement inside dense terrain so they gain Hidden, "
          "which makes them untargetable beyond 15\" (12\" when the shooter's view is "
          "broken by dense terrain).",
    detail="11e's Hidden rule (core rules 13.09) gives INFANTRY/BEASTS/SWARM in a "
           "dense terrain area a detection range — enemies further away simply cannot "
           "target them, regardless of line of sight. Good players treat 'get to hidden "
           "12' as the primary movement objective for infantry in the first two rounds, "
           "because it converts an entire enemy shooting phase into nothing. The 3\" "
           "reduction for being obscured by dense terrain is deliberately farmed, not "
           "incidental.",
    confidence="high",
    evidence=[
        ev("40K Dirtbags", "0Gcpze1G4Lc", "10:00",
           "I try and get that dense cover for the hidden 12 ... How fast can I get to hidden 12"),
        ev("Happy Krumping", "SkaqF6vbCYA", "12:00",
           "elite infantry is incredibly powerful, making use of the hidden rule ... can't be targeted outside of 15 or 12"),
        ev("Tabletop Titans", "dPFfT2IIlME", "15:00",
           "if you want to be a shooting army right now ... you have to be able to get within hidden range quickly"),
        ev("Planet 40K", "HQ0sQa37uHA", "13:00",
           "as it's a monster, you're not going to be getting the hidden keyword"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "new_heuristic",
        "target": "_score_movement_destination (movement scoring) — new WEIGHT_HIDDEN_GAINED constant",
        "current_behaviour": "AIDecisionMaker.gd contains zero references to 'hidden' "
                             "(grep -ci hidden = 0), while RulesEngine.gd fully implements 13.09 "
                             "(hidden_model_visible_to, TerrainManager.detection_range_inches_for, "
                             "15\" base minus a 3\" dense penalty). The AI therefore benefits from "
                             "Hidden only by accident when a destination happens to be in terrain.",
        "suggested_change": "Add a movement-destination bonus (start ~4.0, comparable to "
                            "SECONDARY_POSITIONAL_BONUS 4.0) when the destination puts an "
                            "INFANTRY/BEASTS/SWARM unit inside a dense terrain area and the unit "
                            "has not shot this turn. Scale by how many enemy units are further "
                            "than the detection range returned by "
                            "TerrainManager.detection_range_inches_for — a Hidden position that "
                            "hides from nothing is worth nothing.",
        "risk": "Over-weighting drags infantry into terrain and off objectives; Hidden does "
                "not stop charges or blast/indirect, so a Hidden unit can still be run down. "
                "Gate it against the objective VP estimator so it never outbids a scoring move.",
    },
    priority="high",
)

add(
    decision="positioning_and_concealment", faction="general",
    claim="Shooting surrenders Hidden for this turn and the next, so a unit that "
          "cannot meaningfully hurt anything should hold its fire and stay untargetable.",
    detail="Hidden requires that the unit made no ranged attacks this turn or last turn, "
           "so pulling the trigger is a two-turn commitment to being shootable. Players "
           "explicitly weigh a marginal shooting phase against a turn of immunity, and "
           "will decline shots with backfield or objective-holding infantry to keep the "
           "state. This is a genuine per-unit decision every shooting phase, not a "
           "list-building consideration.",
    confidence="high",
    evidence=[
        ev("Zeeto", "TJQWtTZiP1g", "58:00",
           "as soon as you give up hidden, you shoot a ball across the map ... you've got the 15 inch hidden anyway"),
        ev("Mid Table Tactics", "k-IMme1pngY", "42:00",
           "They're not going to be hidden though because they are probably going to shoot"),
        ev("TacticalTortoise 40k", "VqwMdS9MuIY", "186:00",
           "I'm hidden in the line like this cuz I just got to shoot there ... not hidden cuz they're shooting"),
        ev("Proxy Hammer", "f_z0hvW0VMk", "49:00",
           "you don't have to move out into the open ... remain hidden even while shooting"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "new_heuristic",
        "target": "shooting-phase target scoring — new HIDDEN_FORFEIT_PENALTY constant",
        "current_behaviour": "The AI shoots whenever a legal shooting action scores above "
                             "zero. It has no concept of a non-damage cost to firing, so it will "
                             "trade two turns of untargetability for one low-value shooting action.",
        "suggested_change": "When the shooter is currently Hidden, subtract a penalty from every "
                            "shooting assignment for that unit — scale it by how many enemy units "
                            "are outside detection range (i.e. how much immunity is being sold). "
                            "Suggested start: 3.0, so the unit still fires when the expected "
                            "damage is real but declines chip shots.",
        "risk": "An over-large penalty produces a passive gunline that never shoots. The penalty "
                "must be zero for units that already shot this turn (Hidden is already lost) and "
                "for units with a 'remain hidden while shooting' ability.",
    },
    priority="high",
)

add(
    decision="target_selection", faction="general",
    claim="Enemy infantry that is about to regain Hidden should be shot this turn, "
          "because next turn it may be untargetable.",
    detail="Hidden returns once a unit goes a full turn without shooting, so an enemy "
           "unit that fired last turn but not this one is on a timer. Players consciously "
           "reprioritise onto those units while the window is open, rather than picking "
           "the highest-value target and finding it unshootable next turn. This is the "
           "mirror image of the decision to hold fire.",
    confidence="medium",
    evidence=[
        ev("Boltgun Tactics", "gRQZh-QYBIQ", "20:00",
           "I'm not going to shoot the raptors cuz they might get hidden um if I don't shoot"),
        ev("40K Dirtbags", "Enm67qaqHkU", "07:00",
           "these guys won't be able to shoot me turn one if everybody's hidden"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "weight_constant",
        "target": "_calculate_target_value — new HIDDEN_WINDOW_BONUS",
        "current_behaviour": "Target value is computed from points, output, survivability and "
                             "objective presence. Availability is treated as binary and permanent: "
                             "there is no notion of a target that is legal now and illegal later.",
        "suggested_change": "Multiply target value by ~1.25 when the target is an "
                            "INFANTRY/BEASTS/SWARM unit standing in dense terrain that did not "
                            "make ranged attacks this turn — it will be Hidden on the opponent's "
                            "next turn. Read the same flags RulesEngine uses for 13.09.",
        "risk": "Chasing the window can pull fire off a genuinely more dangerous target. Keep the "
                "multiplier modest so it breaks ties rather than overriding threat.",
    },
    priority="medium",
)

add(
    decision="positioning_and_concealment", faction="general",
    claim="Every move into enemy line of sight is taxed by Overwatch, which in 11e "
          "fires at the end of the opponent's Movement phase and can no longer be baited "
          "out with a single expendable model.",
    detail="Overwatch moved to the end of the opponent's Movement phase and uses snap "
           "shooting (hits only on unmodified 6s, no re-rolls). Because the defender now "
           "watches the whole movement phase resolve before choosing a target, the old "
           "trick of pushing one cheap model out to draw the shot is dead — the defender "
           "simply waits and picks the best target. Players describe this as having to "
           "declare their whole movement plan to the opponent before paying for it.",
    confidence="high",
    evidence=[
        ev("Vanguard Tactics", "qahZnQPN8a8", "27:00",
           "Overwatch is so powerful in this game now because you can't ... put one model out ... you can't bait them out anymore"),
        ev("StrikingScorpion82", "eUpeWbN7gF4", "28:00",
           "overwatch is done at the end of the opponent's movement phase ... it's a decision we can make uh once movement's done"),
        ev("Deploy on the Line 40K", "FT5JoL5Myis", "05:00",
           "it's just too easy to overwatch in 11th edition. You can't play around it anymore with these big squads"),
        ev("6 Plus Plus Gaming", "uKl8cEJlk0c", "27:00",
           "with how Overwatch is now, that's really really powerful to have a reactive move"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "weight_constant",
        "target": "THREAT_SHOOTING_PENALTY (currently 0.5)",
        "current_behaviour": "THREAT_SHOOTING_PENALTY is 0.5 and commented 'Lighter penalty for "
                             "moving into shooting range (reduced from 1.0 — often unavoidable)'. "
                             "That reasoning was written for a shooting phase the mover could "
                             "answer; 11e Overwatch is paid inside the mover's own turn, before "
                             "it acts.",
        "suggested_change": "Raise THREAT_SHOOTING_PENALTY to ~1.0 and add a separate "
                            "OVERWATCH_EXPOSURE_PENALTY applied only when the destination is "
                            "visible to an enemy unit that has not yet used Fire Overwatch this "
                            "round, weighted by that unit's raw shot volume (snap shooting rewards "
                            "volume and torrent, not quality). Do not apply it to destinations "
                            "already inside enemy line of sight before the move.",
        "risk": "Too high and the AI refuses to cross the board at all, which loses on primary. "
                "The penalty should be suppressed for melee-archetype units (they already "
                "discount threat via THREAT_MELEE_UNIT_IGNORE) and in rounds 4-5.",
    },
    priority="high",
)

add(
    decision="positioning_and_concealment", faction="general",
    claim="The default opening is to stage the army out of line of sight behind mid-board "
          "terrain and physically occupy the staging point the opponent wants.",
    detail="Because shooting is punishing and Hidden is available, the first-turn move is "
           "usually to get behind the centre ruin rather than onto the mid-board objectives. "
           "The refinement is that the terrain piece is a contested resource: putting bodies "
           "against it denies the opponent the same protection, so the move is simultaneously "
           "defensive and a denial play.",
    confidence="medium",
    evidence=[
        ev("40K Fireside", "-Bh3n-_Tpfs", "61:00",
           "move block your opponent from touching the middle ruin and staging your army behind it"),
        ev("Master Crafted", "6Lgr1hUGsgw", "14:00",
           "we're behind it, we're hidden, they can't see us, but at least we know that we're taking up the space"),
        ev("Play On Tabletop", "1SRkN4Drhs4", "18:00",
           "my jumpack intercessors will move to stage behind this terrain ... I just don't want to be shot"),
        ev("Auspex Tactics", "mX7VBM9qJjY", "07:00",
           "staged as far forward as possible but out of line of sight"),
    ],
    rules_status="player_opinion",
    ai_impact={
        "seam": "weight_constant",
        "target": "CORRIDOR_BLOCK_SCORE_BASE (7.0) / CORRIDOR_BLOCK_POSITION_RATIO (0.55)",
        "current_behaviour": "Corridor blocking already exists but is keyed to objectives — it "
                             "places blockers 55% of the way from an objective toward a threatening "
                             "enemy. It has no notion of terrain pieces as the thing worth denying.",
        "suggested_change": "Extend the corridor-block candidate set with the mid-board dense "
                            "terrain areas TerrainManager already exposes, scoring a blocking "
                            "position that both breaks enemy line of sight to our army and sits "
                            "against the terrain the enemy would otherwise stage in. Reuse "
                            "CORRIDOR_BLOCK_SCORE_BASE so the two compete on one scale.",
        "risk": "Terrain-hugging can strand units away from scoring positions in rounds 4-5, where "
                "STRATEGY_LATE_OBJECTIVE (1.6) should dominate. Gate to rounds 1-2.",
    },
    priority="medium",
)

# ------------------------------------------------------------------ screening
add(
    decision="screening_and_zoning", faction="general",
    claim="A screen is defined by the gaps between its models relative to the enemy's "
          "base size, not by the unit's overall position — gaps must be too narrow for an "
          "enemy base to pass through while staying more than 1\" away.",
    detail="Models cannot move within Engagement Range of enemies during a normal move, so "
           "two screening models placed a base-width-plus-2\" apart form a wall; placed wider, "
           "they are decoration. Players talk in terms of the specific enemy base they are "
           "screening against (32mm, 2\"), and losing a game to a single unplanned gap is a "
           "recurring post-mortem. Consolidation compounds the error: a model that squeezes "
           "through kills the screen and then consolidates into whatever was behind it.",
    confidence="high",
    evidence=[
        ev("6 Plus Plus Gaming", "gRqdSBkqVlA", "22:00",
           "What I didn't think of was leaving gaps between my models to screen a 32 mil base"),
        ev("TacticalTortoise 40k", "VqwMdS9MuIY", "514:00",
           "create a gap that is less than 1 in between all of those models ... will prevent any orc model from going through"),
        ev("Proxy Hammer", "xFGyuYmXyJY", "10:00",
           "you can have a little bit of space in between your models that they won't be able to actually fit through"),
        ev("Grimdark Breakdown", "VPTL092E0VI", "13:00",
           "The amount of times that I have tried to screen and there's a tiny hole"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "new_heuristic",
        "target": "screening placement (SCREEN_SCORE_BASE path) — new SCREEN_MODEL_GAP logic",
        "current_behaviour": "Screening is scored at unit granularity: SCREEN_SPACING_PX (18\") "
                             "spaces whole screening units, and AI_B2B_GAP_PX (0.5px) is only used "
                             "for base-to-base packing. Nothing checks whether the resulting model "
                             "line has a passable gap.",
        "suggested_change": "When laying out a unit flagged as a screener, cap inter-model spacing "
                            "at (largest enemy base diameter + 2\") and validate the finished line "
                            "against the widest enemy base on the board. Expose the cap as "
                            "SCREEN_MAX_MODEL_GAP_PX so it is tunable per profile.",
        "risk": "Tight spacing shortens the screen, so fewer inches are covered per unit and "
                "blast weapons get better value. It also interacts with unit coherency — the "
                "layout must still satisfy coherency after casualties.",
    },
    priority="high",
)

add(
    decision="screening_and_zoning", faction="general",
    claim="Deep-strike denial must use the arriving unit's own minimum distance, because "
          "6\" deep strike is common in 11e and a 9\"-spaced screen does not stop it.",
    detail="Numerous 11e detachments and enhancements grant deep strike at 6\" rather than "
           "the core 9\", and players describe having to screen 'really aggressively' as a "
           "result. Denial geometry is the sum of two radii: to deny a 9\" arrival, screeners "
           "must be within 18\" of each other; to deny a 6\" arrival, within 12\". Using one "
           "fixed number under-screens against exactly the units most able to punish it.",
    confidence="high",
    evidence=[
        ev("Odyssey40k", "uYFHWwWSklU", "87:00",
           "there's a 6-in deep strike in retaliation ... you have to screen really aggressively for it"),
        ev("Tactical Sugar", "SyVxk7EW_tI", "132:00",
           "it's so much harder screen out now in 11th and deep strikes are so much more important in 11th"),
        ev("TacticalTortoise 40k", "nGqRAvAMTYA", "66:00",
           "He also can 6 in deep strike high OC onto an objective in order to grab it"),
        ev("The Tabletop Alliance 40K", "8_HAdKldvhs", "20:00",
           "What do you have in reserve? Screamers ... 6 in deep strike now"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "weight_constant",
        "target": "DEEP_STRIKE_DENIAL_RANGE_PX (360.0 = 9\") and SCREEN_SPACING_PX (720.0 = 18\")",
        "current_behaviour": "Both constants are hardcoded to the core-rules 9\" case. "
                             "_find_screening_positions steps the board every SCREEN_SPACING_PX and "
                             "treats any point further than DEEP_STRIKE_DENIAL_RANGE_PX from a "
                             "friendly model as deniable.",
        "suggested_change": "Derive the radius per threat: scan enemy units still in reserve for a "
                            "deep-strike ability naming a distance, take the minimum across them, "
                            "and use 2x that as the screen spacing for this game. Keep the current "
                            "values as the fallback when no reserve unit advertises a shorter range.",
        "risk": "A 12\" spacing needs ~50% more screening bodies to cover the same frontage; on "
                "low-model armies this will starve objectives. Pair with a cap on how many units "
                "may take screening assignments.",
    },
    priority="high",
)

# ------------------------------------------------------------ target selection
add(
    decision="target_selection", faction="general",
    claim="Clearing enemy screens is worth more than the screen's points, because the "
          "screen is what stops the rest of the army from scoring or charging.",
    detail="Players routinely commit an expensive unit to kill a cheap one and describe it "
           "as a good decision, because the cheap unit is denying a charge lane, an objective, "
           "or a deep-strike landing zone. Points-per-wound efficiency scores this as a bad "
           "trade; the players' framing is that the screen's value is the value of everything "
           "it is blocking. The counterweight they also state is not to use your best melee "
           "unit on chaff when a cheaper one will do.",
    confidence="high",
    evidence=[
        ev("TacticalTortoise 40k", "VqwMdS9MuIY", "62:00",
           "it's absolutely worth a genailer squad to eviscerate one of those ranger squads even though it's a trade down"),
        ev("40K Fireside", "_xKjN6N1jT0", "04:00",
           "you need to kill like I don't know, 10 guardsmen move blocking your big charges"),
        ev("TacticalTortoise 40k", "7AgzQIEq3j4", "93:00",
           "you can clear screening units and infiltrators ... have to run 20 possessed into ... 10 commandos"),
        ev("Warpbane Tactics", "D5XVd0FRgK8", "02:00",
           "unit left alive on one wood can still hold an objective, block our movement ... That is why finis"),
    ],
    rules_status="player_opinion",
    ai_impact={
        "seam": "weight_constant",
        "target": "TRADE_PPW_WEIGHT (0.25) / TRADE_UNFAVORABLE_PENALTY (0.7)",
        "current_behaviour": "Trade analysis penalises killing cheap units with expensive ones "
                             "(TRADE_UNFAVORABLE_PENALTY 0.7), and is gated to Competitive "
                             "difficulty only (use_trade_analysis). A screening unit is scored as "
                             "its points and output, so it looks like a bad target.",
        "suggested_change": "Add a positional-value term to _calculate_target_value: if the target "
                            "is currently inside our own screening-denial evaluation (it is blocking "
                            "a charge lane, sitting in a deep-strike landing zone we want, or "
                            "contesting an objective our VP estimator prices), suppress the "
                            "TRADE_UNFAVORABLE_PENALTY for that target rather than adding raw score. "
                            "Suppression, not a bonus, keeps the existing scale intact.",
        "risk": "Suppressing the penalty too broadly recreates the pre-trade-analysis behaviour of "
                "shooting lascannons at Grots. It must key off an explicit blocking role, not off "
                "cheapness.",
    },
    priority="high",
)

add(
    decision="target_selection", faction="general",
    claim="Battle-shocking a unit strips its Objective Control to zero, so an objective can "
          "be flipped without killing anything.",
    detail="A battle-shocked unit's models have OC '-', cannot be targeted by stratagems and "
           "cannot start actions. Players describe whole lists built around it ('battleshock OC "
           "denial') and use forced battle-shock tests specifically to deny a primary score in "
           "the opponent's command phase. Against durable objective-holders this is far cheaper "
           "than killing them, and it is the counter to armies that ignore attrition.",
    confidence="high",
    evidence=[
        ev("Zeeto", "TJQWtTZiP1g", "02:00",
           "That sort of Battleshock um OC denial sort of list ... would probably work well in teams"),
        ev("6 Plus Plus Gaming", "eokQteHr0Fo", "19:00",
           "if you really need them to not have a secondary uh primary point ... it's a really powerful strategy"),
        ev("Grimdark Breakdown", "qwnHaQvzCq0", "14:00",
           "If you Battle Shock me, I go to 1 OC instead of 0"),
        ev("The Six Machine", "ewxyBDMvC64", "23:00",
           "it is more likely that you will get battleshocked and potentially stay battleshocked"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "new_heuristic",
        "target": "objective contest evaluation + battle-shock-inflicting ability/stratagem scoring",
        "current_behaviour": "The AI reads the battle_shocked flag defensively (it un-shocks its "
                             "own units via 'Da Captain', and skips shocked enemies in some checks) "
                             "but never evaluates inflicting battle-shock as a route to controlling "
                             "an objective. Objective contest is computed from raw OC only.",
        "suggested_change": "When scoring an ability or stratagem that forces a battle-shock test, "
                            "add the VP the objective would be worth if the target's OC went to "
                            "zero — reuse _estimate_objective_vp_value with the target's OC removed "
                            "and score the delta. Same term should make a shocked enemy unit a "
                            "lower-priority shooting target while it is shocked and already "
                            "contributing nothing.",
        "risk": "Battle-shock is a leadership roll and often fails; the score must be multiplied by "
                "the actual pass probability or the AI will spend CP on coin flips. It also lasts "
                "only until the next command phase, so it is worthless outside the scoring window.",
    },
    priority="high",
)

add(
    decision="target_selection", faction="general",
    claim="Concentrate onto one target until it is destroyed rather than spreading damage; "
          "a unit left on one wound still holds objectives and blocks movement.",
    detail="A surviving model retains full Objective Control and full blocking geometry, so "
           "partial damage buys almost nothing in a mission-scored edition. Players describe "
           "spreading fire as the specific mistake that cost them a game, and finishing "
           "targets as the corrective. This mostly corroborates what the AI already does, but "
           "the mechanism matters: the reason to finish is positional, not damage-economic.",
    confidence="medium",
    evidence=[
        ev("Warpbane Tactics", "PWtaFLZYu_U", "03:00",
           "spreading my damage across multiple units would have been a massive mistake. I focused on completely removing one unit at a time"),
        ev("Warpbane Tactics", "D5XVd0FRgK8", "02:00",
           "unit left alive on one wood can still hold an objective, block our movement"),
        ev("Planet 40K", "lNn0zv_w8t8", "05:00",
           "another bad priority target ... is just simply bad trades"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "weight_constant",
        "target": "MICRO_MARGINAL_KILL_BONUS (2.5) / MICRO_OVERKILL_DECAY (0.35) / OVERKILL_TOLERANCE (1.15)",
        "current_behaviour": "Focus fire already exists at Normal+ and MICRO_MARGINAL_KILL_BONUS "
                             "rewards the assignment that crosses the kill threshold. The weighting "
                             "is damage-denominated, so a target holding an objective is not "
                             "preferentially finished.",
        "suggested_change": "Multiply MICRO_MARGINAL_KILL_BONUS by ~1.4 when the target currently "
                            "contributes OC to an objective our VP estimator prices above zero, so "
                            "finishing a scoring unit outbids starting on a fresh one.",
        "risk": "Low. The main hazard is stacking with the disposition kill-pressure term and "
                "producing tunnel vision on one objective.",
    },
    priority="medium",
)

# --------------------------------------------------------------- objectives
add(
    decision="objective_trade", faction="general",
    claim="Tabling the opponent is no longer a win condition in 11e; the AI should accept "
          "losing units it cannot save if the exchange keeps it ahead on primary.",
    detail="Multiple channels contrast 11e with 10e explicitly: in 10e killing the opponent's "
           "army was a common route to victory, in 11e games are decided on accumulated primary "
           "and secondary VP with a 45-point primary cap. The practical consequence is that a "
           "durable army can lose the attrition war and still win, and an aggressive army that "
           "wins every fight can lose on points.",
    confidence="high",
    evidence=[
        ev("Grimdark Breakdown", "MG546BN181w", "47:00",
           "You do not have to kill your opponent in 11th edition. A giant condition of winning was tableabling your opponent in 10th"),
        ev("Master Crafted", "9fuvetVLB3s", "29:00",
           "they don't have to kill you. It's just going to take you five turns to kill their army and they're just going to keep scoring"),
        ev("40K Dirtbags", "EBJW0VDeT_Q", "45:00",
           "win on primary by denying primary and stuff like that. It's really the only way to to win 40k"),
        ev("Deploy on the Line 40K", "VU4S_6e1NgE", "24:00",
           "you're just going to win on primary points as long as you don't burn out"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "weight_constant",
        "target": "STRATEGY_EARLY_AGGRESSION (1.3) / STRATEGY_EARLY_OBJECTIVE (0.95)",
        "current_behaviour": "Rounds 1-2 boost kill-seeking 30% and hold objective weight just "
                             "below full (0.95). The VP-denominated objective estimator already "
                             "exists, so the framework is right, but the early-round modifiers "
                             "still tilt toward damage.",
        "suggested_change": "Bring STRATEGY_EARLY_AGGRESSION down toward 1.1 and "
                            "STRATEGY_EARLY_OBJECTIVE up to 1.0, and A/B it the way "
                            "orks_discipline_a.json A/B'd the Ork constant. Do not change the late "
                            "modifiers — they already favour objectives.",
        "risk": "Reduced early aggression can let an aggressive opponent establish the mid-board "
                "unopposed, which loses on primary for the opposite reason. This is a benchmark "
                "question, not a settled one — hence the profile arm rather than a constant edit.",
    },
    priority="medium",
)

add(
    decision="objective_trade", faction="general",
    claim="The force disposition should modulate how much the AI values killing versus "
          "holding, not just which objectives it prices.",
    detail="11e pairs each player's disposition deck against the opponent's, and the five "
           "dispositions reward very different behaviour: Purge the Foe pays for destroying "
           "units every turn, Take and Hold pays for straightforward objective control, "
           "Recon and Priority Assets pay for actions in specific places, and Disruption "
           "scores poorly overall — which players treat as licence to stop caring about "
           "scoring and simply attack. That last inversion is the clearest evidence that "
           "disposition should change aggression, not only objective pricing.",
    confidence="medium",
    evidence=[
        ev("Happy Krumping", "pAk1YiuioNQ", "70:00",
           "disruption scores poorly, it kind of releases you to not have to worry about scoring ... you might as well just obliterate your opponents"),
        ev("Deploy on the Line 40K", "14LSO7MS3QI", "85:00",
           "if they were taking recon they're just trying to kill people and say whatever you score your points later"),
        ev("Warpbane Tactics", "ogMKXBVh4g0", "02:00",
           "Disruption is about interfering with your opponent's plans, it rewards movement, positioning"),
        ev("TacticalTortoise 40k", "i7MkaccGXeA", "25:00",
           "gives you points where you destroy enemies ... So it's a simply a race"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "new_heuristic",
        "target": "_build_primary_awareness → feed kill_pressure into the aggression modifier stack",
        "current_behaviour": "_build_primary_awareness already parses the player's own 11e primary "
                             "card and sets objective_pressure, enemy_home_bonus, central_bonus and "
                             "a boolean kill_pressure. objective_pressure feeds objective scoring, "
                             "but kill_pressure is only recorded — it does not modify the "
                             "aggression/charge-threshold modifiers.",
        "suggested_change": "Multiply the aggression modifier by ~1.2 and the charge threshold by "
                            "~0.9 while awareness.kill_pressure is true, and apply the inverse when "
                            "objective_pressure is high and kill_pressure false. This is a small "
                            "change because the parsing already exists.",
        "risk": "Double-counting: kill-based primary rules already raise the VP value of killing "
                "through the estimator, so a second multiplier can over-rotate. Cap the combined "
                "aggression modifier.",
    },
    priority="medium",
)

# ----------------------------------------------------------------- reserves
add(
    decision="reserves_and_arrival", faction="general",
    claim="Keeping one unit in reserve as a reactive answer is standard, but committing "
          "the whole army to the table is correct against high-pressure lists — the corpus "
          "genuinely disagrees on how much to hold back.",
    detail="One camp treats a reserve unit as a deliberate list slot: something held to "
           "answer whatever the opponent commits, or to Rapid Ingress into a gap. The other "
           "camp says that against lists which apply immediate pressure you need every body "
           "on the table from turn one, because arriving later means arriving after the "
           "mid-board is lost. Both are stated confidently by strong players; the resolving "
           "variable appears to be the opponent's speed, which the AI can measure.",
    confidence="medium",
    evidence=[
        ev("40K Dirtbags", "Enm67qaqHkU", "04:00",
           "at least one unit in reserves cuz you're making lists to have a reserve rapid ingress target"),
        ev("Art of War 40k", "ym0SnzF2ydg", "162:00",
           "maybe they should have just started the game in reserve so they could be a little bit more of a reactive answer"),
        ev("Happy Krumping", "pAk1YiuioNQ", "09:00",
           "If you're ever going to play against it, don't start things in reserves. You need everything on the table"),
        ev("Deploy on the Line 40K", "gZWxrJy66nw", "12:00",
           "there's no reason to put anything in reserve because I have redeploy"),
    ],
    rules_status="player_opinion",
    ai_impact={
        "seam": "new_heuristic",
        "target": "_evaluate_reserves_declarations",
        "current_behaviour": "Reserves selection puts melee-oriented and short-range deep-strike "
                             "units into reserve up to the 50% points / 50% units cap, without "
                             "reference to how fast the opponent's army is.",
        "suggested_change": "Before declaring reserves, compute the opponent's effective turn-one "
                            "threat range (max Move + Advance + charge across their deployed units, "
                            "plus scout moves). Above a threshold (~20\"), reduce the reserve budget "
                            "toward one unit; below it, keep the current behaviour. Expose the "
                            "threshold as RESERVE_PRESSURE_THRESHOLD_INCHES.",
        "risk": "Threat range is a crude proxy — an army can be fast and harmless. Getting it wrong "
                "in the aggressive direction leaves the AI with nothing in reserve against alpha "
                "strikes, which is the failure mode the second camp is warning about.",
    },
    priority="medium",
)

add(
    decision="reserves_and_arrival", faction="general",
    claim="Reactive movement abilities are widespread enough in 11e that the AI cannot "
          "treat enemy positions as fixed between its own decisions.",
    detail="Detachment rules, enhancements and stratagems across many factions grant a move "
           "triggered by an enemy action — being shot, or an enemy coming within a set "
           "distance. Players plan around it explicitly: they decline moves that would trigger "
           "a reactive escape, and they buy reactive-move abilities specifically as insurance "
           "against 11e's stronger Overwatch. Any AI plan that assumes the target stays put "
           "will systematically over-value long charges and precise blocking positions.",
    confidence="medium",
    evidence=[
        ev("PNW 40K", "ycW5l0xHp9s", "08:00",
           "He can make a reactive move ... reactive moves in general are very powerful"),
        ev("HivemindHobbies", "Wm2Hd8h74_o", "65:00",
           "if he moves up at all, then they will automatically reactive move behind this obscuring wall"),
        ev("40K Dirtbags", "Enm67qaqHkU", "20:00",
           "he then reactive moves and kind of spreads out to stop Ghaz from moving this way"),
        ev("TacticalTortoise 40k", "VqwMdS9MuIY", "60:00",
           "it has the ability to reactive move to enemies going close to it ... it may be able to jump away"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "difficulty_gate",
        "target": "AIDifficultyConfig.use_look_ahead (Competitive only)",
        "current_behaviour": "Look-ahead is Competitive-only and models opponent responses "
                             "generically. Nothing detects that a specific enemy unit owns a "
                             "reactive-move ability.",
        "suggested_change": "Scan enemy datasheet abilities and the opponent's detachment "
                            "stratagems for reactive-move wording, and discount blocking-position "
                            "and marginal-charge scores against those units by ~30%. Gate to "
                            "Hard+ rather than Competitive-only, since it is a defensive "
                            "correction rather than deep search.",
        "risk": "Ability-text scanning is brittle and will both miss and over-match. A false "
                "positive makes the AI refuse good charges. Prefer an explicit ability list over "
                "free-text matching.",
    },
    priority="medium",
)

# ------------------------------------------------------- melee / lock / actions
add(
    decision="melee_commitment", faction="general",
    claim="Charging purely to tie up a dangerous shooter is worth doing even when the "
          "charging unit expects to deal and receive negligible damage.",
    detail="A unit locked in engagement generally cannot shoot, so a cheap charge can switch "
           "off an expensive gun for a full turn. Players make this charge knowing they will "
           "lose the melee, and specifically use it against vehicles and gunline units that "
           "would otherwise fire freely. The value is the enemy's forgone shooting phase, not "
           "the combat result.",
    confidence="medium",
    evidence=[
        ev("WednesdayNightWarhammer", "MkeH0tr1o_o", "57:00",
           "I guess I would attempt the charge to get just to tie you up"),
        ev("40K Dirtbags", "0Gcpze1G4Lc", "14:00",
           "this thing was within range to move up and shoot her. So, I needed to make this charge to stop this tank"),
        ev("WarGames Live", "HER6VzUGO60", "658:00",
           "We'll charge the truck in just to lock you in because we can still touch you and still be on the objective"),
        ev("Mordian Glory", "lp4j3iYlpQ4", "25:00",
           "I charged up to the hell hound just to tie them up again"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "weight_constant",
        "target": "PHASE_PLAN_LOCK_SHOOTER_BONUS (3.0) / PHASE_PLAN_RANGED_STRENGTH_DANGEROUS (5.0)",
        "current_behaviour": "The multi-phase planner already gives a 3.0 bonus for charging "
                             "dangerous shooters, but it is gated behind use_multi_phase_planning "
                             "(Hard+), and the charge must still clear the normal charge threshold "
                             "that is driven by expected damage.",
        "suggested_change": "Make the lock bonus able to carry a charge on its own: when the target "
                            "exceeds PHASE_PLAN_RANGED_STRENGTH_DANGEROUS and the charger is cheap "
                            "relative to it, bypass the expected-damage component of the charge "
                            "threshold rather than adding to it. Consider lowering the gate to "
                            "Normal, since players treat this as basic play.",
        "risk": "Feeding cheap units into melee they lose can hand the opponent Purge-the-Foe VP "
                "and free consolidation moves toward objectives. Require that the charger is not "
                "currently contributing OC to a priced objective.",
    },
    priority="medium",
)

add(
    decision="melee_commitment", faction="general",
    claim="Consolidation should be scored as a positioning move — onto an objective, into "
          "a new enemy unit, or backwards out of line of sight — not as a default 3\" shuffle.",
    detail="After fighting, the 3\" consolidation is often the most valuable move of the turn: "
           "it can put a unit onto an objective it could not have charged, drag it into a "
           "second enemy unit to lock that one too, or pull it back behind terrain so it is "
           "not shot in the opponent's turn. Players choose deliberately between those three "
           "outcomes and name the reason each time.",
    confidence="medium",
    evidence=[
        ev("40K Dirtbags", "Enm67qaqHkU", "24:00",
           "I picked this objective to cons consolidate backwards a little bit so he doesn't get shot"),
        ev("Maelstrom Gaming Studios - Tyranids", "aQsog-fkQJ8", "71:00",
           "I will tow this guy onto the objective ... get a tiny bit further away"),
        ev("Auspex Tactics", "YM1sRZGVOhw", "12:00",
           "If you're able to hit something, destroy something, consolidate into something else"),
        ev("Boltgun Tactics", "6V8asnfgFUE", "161:00",
           "We'll just consolidate into the middle"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "new_heuristic",
        "target": "consolidation move selection in the FIGHT phase",
        "current_behaviour": "Consolidation is resolved without a dedicated scoring pass "
                             "comparable to _score_movement_destination; there is no explicit "
                             "objective/LoS evaluation of the 3\" options.",
        "suggested_change": "Score consolidation destinations with the same three terms used for "
                            "movement — objective VP delta (via _estimate_objective_vp_value), "
                            "number of additional enemy units brought into engagement, and whether "
                            "the destination breaks enemy line of sight — and pick the max.",
        "risk": "Consolidating out of line of sight can also leave an objective; the VP term must "
                "dominate. Rules constraints on consolidation (must end closer to the nearest "
                "enemy, or toward an objective) restrict the legal set and must be respected.",
    },
    priority="medium",
)

add(
    decision="disengage_and_lock", faction="general",
    claim="Falling back is expensive: most vehicles cannot fall back and shoot, and a "
          "battle-shocked unit must make Desperate Escape rolls, so staying locked is often "
          "correct.",
    detail="Fall Back normally forbids shooting and charging for the rest of the turn unless "
           "a specific ability says otherwise, and that ability is usually restricted to "
           "infantry. Players are caught out by this mid-game. The corollary drives the "
           "opposite decision too: armies that want the enemy stuck deliberately engage from "
           "multiple units so that falling back is unattractive.",
    confidence="medium",
    evidence=[
        ev("40K Dirtbags", "F5TL7LhZJlY", "13:00",
           "He spends a CP realizing after the fact that you can't fall back and shoot with vehicles. It's only infantry"),
        ev("40K Dirtbags", "Enm67qaqHkU", "25:00",
           "If they fall back and shoot, these guys could have fell back and shot. But that's only one unit of shooting"),
        ev("Maelstrom Gaming Studios - Tyranids", "aQsog-fkQJ8", "98:00",
           "no, we'll fall back and we'll take our hazardous roles. Ones and twos, they die"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "weight_constant",
        "target": "SURVIVAL_FALL_BACK_BONUS (2.0) / SURVIVAL_HOLD_BONUS (1.5)",
        "current_behaviour": "Survival assessment (Normal+) compares expected damage against "
                             "remaining wounds and adds a flat 2.0 toward falling back when the "
                             "unit is threatened. The lost shooting phase is not priced.",
        "suggested_change": "Subtract the unit's own expected ranged output from the fall-back "
                            "score unless it has a fall-back-and-shoot ability, and subtract more "
                            "when the unit is battle-shocked (Desperate Escape casualties). A "
                            "VEHICLE without that ability should almost never fall back purely for "
                            "survival.",
        "risk": "Holding a losing combat can lose the unit outright. The change should only "
                "reweight, not veto — SURVIVAL_LETHAL_THRESHOLD (0.75) must still force the "
                "retreat when destruction is likely.",
    },
    priority="medium",
)

add(
    decision="action_economy", faction="general",
    claim="Mission actions consume the acting unit's shooting, so they should be assigned "
          "to the cheapest unit that can reach and survive, not to whatever is nearest.",
    detail="Recon and Priority Assets dispositions are action-heavy, actions are limited to "
           "one per turn on some cards and cannot start before round two on others, and "
           "starting an action generally costs the unit its shooting phase. Players therefore "
           "build in small, cheap, mobile units whose whole job is to walk somewhere and press "
           "a button. Notable exception in 11e: Titanic units can shoot and perform actions.",
    confidence="medium",
    evidence=[
        ev("Grimdark Breakdown", "VPTL092E0VI", "12:00",
           "They have very small bases and then put down somewhere else on the board to do the action"),
        ev("TacticalTortoise 40k", "7AgzQIEq3j4", "10:00",
           "Titanic units can shoot and perform actions. So, it's not actually like that bad"),
        ev("Recon By Fire", "42CPnCfuCN8", "01:00",
           "for one CP, they are capable of shooting and still being able to perform an action"),
        ev("Exile Wargaming", "mbNWzDn6Pu4", "05:00",
           "we have to triangulate objectives by doing actions on them. We can only do one a turn"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "new_heuristic",
        "target": "action assignment (MissionManager._run_primary_auto_actions_11e is the backstop)",
        "current_behaviour": "Primary-card marker/action mechanics are auto-resolved by "
                             "MissionManager as a headless/AI backstop, and _build_primary_awareness "
                             "gives those rule types a flat +1.0 generic objective pressure. There "
                             "is no cost model for which unit performs the action.",
        "suggested_change": "When an action is available, rank candidate units by (expected ranged "
                            "output forgone + points at risk) ascending and pick the cheapest that "
                            "can reach. Skip the forgone-output term for TITANIC units.",
        "risk": "The cheapest unit is often the screening unit; pulling it off a screen to press a "
                "button can open a deep-strike lane. Exclude units currently holding a screening "
                "assignment.",
    },
    priority="medium",
)

add(
    decision="tempo_and_commitment", faction="general",
    claim="In 11e the player who rolls highest must take the first turn, so deployment has "
          "to be robust to going either first or second rather than optimised for a choice.",
    detail="Players describe not having to 'sweat' the first-turn roll because the choice is "
           "gone, and describe being forced into a first turn they did not want for their "
           "disposition. The planning consequence is that a deployment which is only good on "
           "the play, or only good on the draw, is a liability — and that counter-deployment "
           "against what the opponent has already put down matters more than turn-order "
           "gambling.",
    confidence="medium",
    evidence=[
        ev("MiniWarGaming", "dy1zEFAKLzk", "03:00",
           "This is the nice thing about the whoever rolls highest has to go first. I do not have to sweat about who gets first turn"),
        ev("Exile Wargaming", "mbNWzDn6Pu4", "10:00",
           "we did win the dice roll and had to go first, which I don't really like in recon"),
    ],
    rules_status="unverified",
    ai_impact={
        "seam": "difficulty_gate",
        "target": "AIDifficultyConfig.use_counter_deployment (Normal+)",
        "current_behaviour": "Counter-deployment is already enabled from Normal upward, which is "
                             "the right call under this rule. No change is strictly required.",
        "suggested_change": "No weight change. Record the rule so that any future 'choose to go "
                            "second' logic is not written, and so deployment scoring is not tuned "
                            "on an assumed turn order. Verify against the 11e core rules before "
                            "relying on it.",
        "risk": "None — this finding is informational. It is marked unverified because it rests on "
                "two channels' asides rather than a rules quotation.",
    },
    priority="low",
)

# --------------------------------------------------------------- FACTION: Orks
add(
    decision="ability_timing", faction="Orks",
    claim="Waaagh! should not be called in round 1, nor the moment a single unit can reach "
          "something — it wants several units simultaneously in advance-and-charge range, and "
          "its 5+ invulnerable is worth calling for on its own when crossing open ground.",
    detail="Waaagh! is once per battle and grants advance-and-charge, +1 Strength and Attacks "
           "in melee, and a 5+ invulnerable save to the whole army for one battle round. "
           "Because it is a single one-shot, the payoff is the number of units that convert it "
           "into a charge at once; spending it to reach one target wastes the army-wide "
           "component. Players also call it purely defensively, to survive a turn of shooting "
           "while advancing — which means 'how many units can charge' is not the only trigger.",
    differs_from_general="The general-case AI fires a once-per-battle offensive buff as early "
                         "as it can be used, on the reasoning that more turns benefit. Waaagh! "
                         "does not work that way: it lasts one battle round, so early use is "
                         "pure waste, and its value is the count of units that benefit "
                         "simultaneously plus the defensive save for the turn the army is most "
                         "exposed.",
    confidence="high",
    evidence=[
        ev("Tabletop Nexus", "QZ9wggn2oUo", "04:00",
           "Don't call it turn one, though. Don't call it the moment you can reach something"),
        ev("Tabletop Nexus", "QZ9wggn2oUo", "04:00",
           "A strong Waaagh! turn has several units positioned to benefit at once"),
        ev("40K Dirtbags", "DHVBk9vnR8w", "07:00",
           "moved up a little bit like two extra inches forward uh to plan for turn two Waagh"),
        ev("Hubtown Hammer", "vLQTE5P6pJg", "03:00",
           "Turn two, the Orks used the Waagh, which turned out to be a great choice ... blunted by some hot five plus invulnerable"),
        ev("40K Dirtbags", "Enm67qaqHkU", "33:00",
           "if I give up Zod turn one with a Waagh, I spent my Waagh and now I gave up Zod"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "faction_ability",
        "target": "AIDecisionMaker.gd:4481 CALL_WAAAGH block",
        "current_behaviour": "Round 1: calls Waaagh! if ANY single unit is within 22\" of an enemy "
                             "(units_in_range >= 1). Round 2+: calls it unconditionally, with the "
                             "comment 'Round 2+: always use it — waiting loses turns of benefit'. "
                             "The unit count is computed but only used for the log line from round "
                             "2 onward, and the 5+ invulnerable is never considered.",
        "suggested_change": "Replace the round-1 gate with a units_in_range threshold of 3+, and "
                            "replace the unconditional round-2 fire with 'units_in_range >= 3, or "
                            "round >= 4 (use-it-or-lose-it)'. Add a defensive trigger: fire it "
                            "regardless of charge count when more than half the army is inside "
                            "enemy threat range and lacks an invulnerable save. Expose the "
                            "threshold as WAAAGH_MIN_UNITS_IN_RANGE.",
        "risk": "A threshold set too high never fires the ability, which is strictly worse than "
                "firing it late — hence the round-4 backstop. The 22\" advance-and-charge estimate "
                "is centroid-based and optimistic; 3 units at 22\" may be 1 unit in practice.",
    },
    priority="high",
)

add(
    decision="screening_and_zoning", faction="Orks",
    claim="Gretchin exist to absorb the screening and home-objective jobs so Boyz mobs are "
          "never assigned to them.",
    detail="Ork lists carry multiple cheap Gretchin units specifically as job-units: sit on "
           "home, screen the deployment zone, and block deep strike, leaving the 20-model Boyz "
           "mobs free to be the offensive units the army actually wins with. The failure mode "
           "players describe is a Boyz mob that ends up babysitting an objective — a 200-point "
           "unit doing a 40-point unit's job.",
    differs_from_general="The general AI picks screeners by cost threshold "
                         "(SCREEN_CHEAP_UNIT_POINTS 100) and would happily assign a cheap-ish "
                         "melee unit to a screen. For Orks the assignment should be near-absolute: "
                         "Gretchin take these roles first and Boyz take them only when no "
                         "Gretchin remain, even if the Boyz mob is closer.",
    confidence="medium",
    evidence=[
        ev("Tabletop Nexus", "QZ9wggn2oUo", "07:00",
           "Gretchen handle the boring jobs, your home objectives, more screening so boys don't have to"),
        ev("40K Dirtbags", "Enm67qaqHkU", "05:00",
           "we have three units of Gretchen, 120 men, two 10 mans"),
        ev("40K Dirtbags", "DHVBk9vnR8w", "02:00",
           "20-man gretchin with Zagdrod, two 10-man gretchin which I really liked having extra gretchin unit"),
    ],
    rules_status="player_opinion",
    ai_impact={
        "seam": "profile_rule",
        "target": "SCREEN_CHEAP_UNIT_POINTS (100) / SCREEN_SCORE_BASE (8.0)",
        "current_behaviour": "Any unit at or below 100 points is a screening candidate, scored at "
                             "SCREEN_SCORE_BASE 8.0 against objective priorities. Ork Boyz mobs are "
                             "above the threshold so they are not screen candidates, but they are "
                             "still eligible for home-objective assignments.",
        "suggested_change": "Ork profile: lower SCREEN_CHEAP_UNIT_POINTS to ~60 so only Gretchin-"
                            "class units qualify, and raise SCREEN_SCORE_BASE to ~10.0 so those "
                            "units take screening over a marginal objective push. Pair with a rule "
                            "that raises WEIGHT_ALREADY_HELD_OBJ for melee units so Boyz leave held "
                            "objectives.",
        "risk": "If the army has lost its Gretchin, a 60-point threshold leaves nothing eligible "
                "to screen at all. Needs a fallback to the default threshold when no candidate "
                "exists.",
    },
    priority="medium",
)

# ---------------------------------------------------------- FACTION: Custodes
add(
    decision="objective_trade", faction="Adeptus Custodes",
    claim="Custodes cannot screen and score simultaneously; they should concentrate into one "
          "or two bricks and concede board area rather than spreading to cover objectives.",
    detail="With roughly a third of a normal army's unit count, every Custodes unit split off "
           "to hold a marker is a unit missing from the one place the army can win a fight. "
           "Players describe the army as wanting to move as a wrecking ball, and describe "
           "splitting as the mistake. The army's compensation is that its units are individually "
           "hard enough to hold an objective against a much larger force, so it can arrive late "
           "and still take the ground.",
    differs_from_general="The general AI spreads units across objectives by score, using "
                         "SUPPORT_STACK_PENALTY (3.5) to actively discourage stacking. For "
                         "Custodes that penalty is backwards: concentration is the plan, and the "
                         "army should accept holding fewer objectives for longer rather than "
                         "contesting more of them briefly.",
    confidence="medium",
    evidence=[
        ev("Tabletop Titans", "EAqaLgAudQo", "216:00",
           "custodians are just not designed that way. They want to be hanging out together just few units but just wrecking ball"),
        ev("Master Crafted", "9fuvetVLB3s", "63:00",
           "it still just didn't feel great as a custod player to have to uh be playing might with purge"),
        ev("Hubtown Hammer", "ET9gYSgKRfs", "04:00",
           "we will always have minus one to hit in the fight phase since they will be within 12 in with the hidden rule"),
    ],
    rules_status="player_opinion",
    ai_impact={
        "seam": "faction_constant",
        "target": "FACTION_AGGRESSION_CUSTODES (1.5) — plus SUPPORT_STACK_PENALTY in the profile",
        "current_behaviour": "Custodes get a single scalar aggression of 1.5, which raises "
                             "kill-seeking and lowers the charge threshold. Nothing changes how "
                             "widely the army spreads; SUPPORT_STACK_PENALTY 3.5 applies as normal "
                             "and pushes units apart.",
        "suggested_change": "This is the clearest evidence that a single 'aggression' scalar is the "
                            "wrong model. For Custodes the differentiating parameter is "
                            "concentration, not aggression: drop SUPPORT_STACK_PENALTY to ~1.5 in "
                            "the Custodes profile and raise WEIGHT_ALREADY_HELD_OBJ toward -1.0 so "
                            "units stay on ground they already hold, while leaving "
                            "FACTION_AGGRESSION_CUSTODES at 1.5.",
        "risk": "Concentration loses to mission formats that reward spread (Recon table quarters, "
                "Priority Assets actions). The profile should be benchmarked per disposition, not "
                "adopted globally.",
    },
    priority="medium",
)

# ---------------------------------------------------------- FACTION: Tyranids
add(
    decision="ability_timing", faction="Tyranids",
    claim="Tyranid battle-shock output is an offensive tempo tool used to strip OC and enable "
          "precision kills, not a passive debuff — the units carrying it should be positioned "
          "aggressively to keep enemies inside its range.",
    detail="Shadow in the Warp and unit-level shock effects turn enemy objective-holders into "
           "OC-0 passengers and open up follow-up plays: players describe shocking a target and "
           "then charging in to precision out the character. That makes the delivery units "
           "(Neurolictors and similar) forward-positioned pieces whose range band matters more "
           "than their survival, which is the opposite of how a support unit is normally played.",
    differs_from_general="The general AI treats support and buff units as things to protect, "
                         "applying THREAT_FRAGILE_BONUS (1.3) to keep high-value fragile units out "
                         "of danger. Tyranid shock-delivery units need to be inside their aura "
                         "range of the enemy's scoring units, which means deliberately accepting "
                         "threat that the general model penalises.",
    confidence="medium",
    evidence=[
        ev("Maelstrom Gaming Studios - Tyranids", "efeKiBbPUPM", "09:00",
           "My Neurolictor battleshocked Volus and the Paladins, which allowed both the Neurolictor and the Hive turret to charge in and precision out"),
        ev("Factions&Fate", "OKoDYKdWm1E", "04:00",
           "infiltrated up here just a little bit past my deployment line, but still within range to hand out battle shocks"),
        ev("winters SEO", "uAmbb_rrUvM", "15:00",
           "shadow in the warp and signapse ... hurts the enemy when they're in range of signapse"),
        ev("TacticalTortoise 40k", "7AgzQIEq3j4", "121:00",
           "force the battle the um shadow in the warp battle shock at a higher penalty"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "profile_rule",
        "target": "THREAT_FRAGILE_BONUS (1.3) / WEIGHT_OC_EFFICIENCY (2.0)",
        "current_behaviour": "Fragile high-value units get an extra threat multiplier and are "
                             "steered away from the enemy. Nothing values keeping an aura source "
                             "within range of enemy units.",
        "suggested_change": "Tyranid profile: reduce THREAT_FRAGILE_BONUS toward 1.0 and add a "
                            "movement term that rewards destinations keeping enemy scoring units "
                            "inside the shock aura's range — mirroring the AAO_RADIUS_INCHES / "
                            "WEIGHT_AAO_ISOLATION pattern already used for Against All Odds.",
        "risk": "Neurolictor-class units are cheap but not expendable; walking them into charge "
                "range hands over kill VP under Purge the Foe. Bound the exposure to units the "
                "enemy cannot reach with a charge this turn.",
    },
    priority="medium",
)

# ------------------------------------------------------- FACTION: Death Guard
add(
    decision="disengage_and_lock", faction="Death Guard",
    claim="Death Guard win by making disengagement expensive rather than by killing — they "
          "should seek to engage multiple enemy units at once and hold them there.",
    detail="Death Guard stack leadership penalties and fall-back punishment, so a unit engaged "
           "by them faces a hard Desperate Escape roll to leave. Players deliberately engage "
           "one enemy unit with two of their own so that the opponent must pass multiple tests, "
           "and describe the army as low-damage but very hard to get away from. The scoring "
           "consequence is that a locked enemy is not shooting and not scoring, which is the "
           "army's whole engine.",
    differs_from_general="The general AI evaluates melee by expected damage and uses "
                         "SURVIVAL_FALL_BACK_BONUS to leave losing fights. Death Guard should "
                         "prefer engagements it does not win on damage, and should value multi-unit "
                         "engagement (more fall-back tests) that the general model treats as "
                         "inefficient over-commitment.",
    confidence="medium",
    evidence=[
        ev("40K Dirtbags", "F5TL7LhZJlY", "23:00",
           "If both of these guys were in combat with the death shroud ... both of them would have to pass a seven up to fall back"),
        ev("Factions&Fate", "OKoDYKdWm1E", "06:00",
           "against you you want to be in melee, so that might benefit me the most"),
        ev("40K Fireside", "u8fm403MGtg", "08:00",
           "Plague Legion it gets stuck in combat a lot and it's really hard to get out of combat"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "profile_rule",
        "target": "PHASE_PLAN_LOCK_SHOOTER_BONUS (3.0) / SURVIVAL_HOLD_BONUS (1.5)",
        "current_behaviour": "Locking bonuses only apply to targets classed as dangerous shooters "
                             "(PHASE_PLAN_RANGED_STRENGTH_DANGEROUS 5.0), and survival assessment "
                             "pulls the AI out of losing fights from Normal upward.",
        "suggested_change": "Death Guard profile: raise PHASE_PLAN_LOCK_SHOOTER_BONUS to ~5.0, "
                            "raise SURVIVAL_HOLD_BONUS to ~3.0 so the AI stays in combats it is "
                            "losing on damage, and lower SURVIVAL_FALL_BACK_BONUS to ~1.0.",
        "risk": "Staying in fights it loses is exactly the failure mode survival assessment was "
                "added to fix; if the enemy can simply kill the engaged unit, this profile feeds "
                "it. Needs benchmarking against a high-damage melee opponent specifically.",
    },
    priority="medium",
)

# --------------------------------------------------------- FACTION: Drukhari
add(
    decision="attrition_and_trades", faction="Drukhari",
    claim="Drukhari should fight out of transports and treat committed squads as expendable — "
          "a squad that disembarks, kills, and dies has done its job.",
    detail="Drukhari infantry are fast and lethal but do not survive being shot, so the "
           "transport is not a delivery convenience but the unit's durability. Players describe "
           "squads as explicitly suicidal — sent to remove a key piece with no expectation of "
           "returning — and describe leaving a unit outside its transport as the error. The "
           "army's economy assumes it trades its units away and keeps scoring with what is left.",
    differs_from_general="The general AI protects expensive and fragile units "
                         "(THREAT_FRAGILE_BONUS 1.3, ARCHETYPE_ELITE_SURVIVAL 1.25) and penalises "
                         "trading an expensive unit into a cheaper one. Drukhari should accept "
                         "those trades when the target is a key enabler, and should weight "
                         "embarkation far more heavily than a general army would.",
    confidence="medium",
    evidence=[
        ev("Deploy on the Line 40K", "jJwrYZs3l-I", "11:00",
           "squad in transport. They're going to suicide themselves"),
        ev("SkaredCast", "nCQuNE_8V44", "19:00",
           "you didn't need the entire unit to kill them. They died very fast. Should have kept them in the transport"),
        ev("6 Plus Plus Gaming", "gRqdSBkqVlA", "07:00",
           "Drukhari really love it in Sky Splinter Assault ... it gives them that bit of protection"),
        ev("MiniWarGaming", "3lwK9jAR0RM", "23:00",
           "going to pick Drazar up to protect Drazar from at least a round of shooting"),
    ],
    rules_status="player_opinion",
    ai_impact={
        "seam": "profile_rule",
        "target": "TRADE_UNFAVORABLE_PENALTY (0.7) / THREAT_FRAGILE_BONUS (1.3)",
        "current_behaviour": "Trade analysis penalises expensive-kills-cheap down to 0.7, and "
                             "fragile high-value units get a 1.3x threat multiplier steering them "
                             "away from danger. Both push against the Drukhari pattern.",
        "suggested_change": "Drukhari profile: raise TRADE_UNFAVORABLE_PENALTY to ~0.9 (nearly "
                            "neutral) and lower THREAT_FRAGILE_BONUS to ~1.0, so committed units "
                            "accept exposure. Add a rule that restores caution in rounds 4-5 "
                            "(round_gte 4 → multiply THREAT_FRAGILE_BONUS by 1.3) so the AI stops "
                            "throwing units away once the trades no longer buy anything.",
        "risk": "Under Purge the Foe the opponent is paid for every unit destroyed, so an "
                "expendable-units profile actively feeds their primary. Benchmark specifically "
                "against a Purge opponent before adopting.",
    },
    priority="medium",
)

# ---------------------------------------------------- FACTION: Space Marines
add(
    decision="ability_timing", faction="Space Marines",
    claim="Oath of Moment should be discounted against targets that our own shooters can "
          "already re-roll into — its value is the re-roll it adds, not the target's threat.",
    detail="Oath grants re-rolls against one enemy unit, so its marginal value collapses when "
           "the units that will actually shoot the target already re-roll hits from another "
           "source. Players state this directly when reviewing lists — a unit hitting on 2s "
           "with re-roll 1s 'does not need Oath of Moment'. The corollary is that Oath goes on "
           "the target the unbuffed portion of the army must kill.",
    differs_from_general="This is a refinement rather than a reversal: the general logic of "
                         "'mark what you most want dead' is right, but for Space Marines "
                         "specifically the score must be computed against the shooters that will "
                         "use it, not against the target in isolation.",
    confidence="medium",
    evidence=[
        ev("Happy Krumping", "pAk1YiuioNQ", "22:00",
           "They already hit on twos ... re-rolling hit rolls of one. They do not need oath of moment"),
        ev("Tabletop Tactics", "eUQmB4CTKlk", "21:00",
           "I'm going to put Oath of Moment on that big brain bug ... he's super tough"),
        ev("Grimdark Breakdown", "qwnHaQvzCq0", "14:00",
           "the only thing you have to remember to do in your Command phase then is ... That's my Oath of Moment target"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "faction_ability",
        "target": "_select_oath_of_moment_target (AIDecisionMaker.gd:4844)",
        "current_behaviour": "Scores each candidate from _calculate_target_value plus target-side "
                             "modifiers: toughness, save, remaining wounds, below-half-strength, "
                             "invulnerable discount, leader-buff bonus, and a 0.5x penalty when the "
                             "army lacks weapons that can hurt it. All modifiers are properties of "
                             "the target; none look at the shooters' existing re-rolls.",
        "suggested_change": "Weight each candidate by the expected damage the army would gain from "
                            "the re-roll, computed over the units likely to shoot it — i.e. sum "
                            "over candidate shooters of (damage with re-roll − damage without), "
                            "and skip shooters that already re-roll hits. This reuses the existing "
                            "_check_army_can_damage_target traversal.",
        "risk": "More expensive to compute each command phase, and it can pick a soft target the "
                "army would have killed anyway. Keep the existing target-side terms as a tiebreak.",
    },
    priority="medium",
)

# ------------------------------------------------------ FACTION: Grey Knights
add(
    decision="objective_trade", faction="Grey Knights",
    claim="Grey Knights teleport (pick a unit up and redeploy it) costs objective control, so "
          "its value is disposition-dependent — under Take and Hold, teleporting a scoring unit "
          "is usually a net loss.",
    detail="Repositioning a unit off an objective removes its OC contribution for the scoring "
           "window, so the same ability that is a free reposition under a kill-oriented card is "
           "a self-inflicted VP loss under an objective-oriented one. The arrival-turn buffs "
           "that reward teleporting are also limited to the turn the unit arrives, so the "
           "benefit is one turn while the objective loss can span two.",
    differs_from_general="A general AI treats a free reposition as unambiguously good. For Grey "
                         "Knights the ability has to be priced against the VP estimator before "
                         "use, and its worth swings with the primary card.",
    confidence="low",
    evidence=[
        ev("Warpbane Tactics", "veM7sLjtdIw", "01:00",
           "being careful about when we use our teleportation. Picking a unit up is incredibly useful, but under Take and Hold, that decision becomes more costly"),
        ev("Warpbane Tactics", "D5XVd0FRgK8", "03:00",
           "Fury of the Titan. Each time one of our units is set up using the deep strike ability until the end of that turn"),
    ],
    rules_status="player_opinion",
    ai_impact={
        "seam": "faction_ability",
        "target": "teleport / redeploy ability scoring",
        "current_behaviour": "Repositioning abilities are scored on the destination's movement "
                             "value. The VP the unit was contributing at its origin is not "
                             "subtracted.",
        "suggested_change": "Subtract _estimate_objective_vp_value for the origin objective from "
                            "the score of any pick-up-and-place ability, so the decision is a net "
                            "VP comparison. This is a general improvement that Grey Knights make "
                            "most visible.",
        "risk": "Low confidence — a single channel. Implement the VP subtraction as general logic "
                "rather than as a Grey Knights special case, and do not ship a Grey Knights "
                "profile on this evidence.",
    },
    priority="low",
)

add(
    decision="target_selection", faction="general",
    claim="Units standing on objectives are premium targets in every round, not just "
          "rounds 4-5, because several common secondaries pay for killing them.",
    detail="'Kill things on objectives' recurs as a secondary across the corpus, and players "
           "reshuffle their whole shooting plan when they draw it — sometimes needing two kills "
           "on markers for full value. Combined with the primary card, an enemy unit on a "
           "marker is being paid for twice: once by removing its OC, once by the secondary. "
           "This is a scoring decision dressed as a target-priority decision.",
    confidence="medium",
    evidence=[
        ev("Tabletop Titans", "Krfpc2el0cA", "25:00",
           "Overwhelming is good. This is kill things on objectives. It's what I want to do ... you really want to try to get two kills"),
        ev("MiniWarGaming", "VvZD_rjUBjE", "19:00",
           "Kill things on the critical objectives with overwhelming force"),
        ev("Play On Tabletop", "TPV3hVKSUxw", "42:00",
           "we've got overwhelming force. So, kill things on objectives"),
        ev("WarGames Live", "1AwnDclFviQ", "552:00",
           "Kill things on objectives. Easy. And do actions"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "weight_constant",
        "target": "STRATEGY_LATE_OBJ_TARGET_BONUS (1.3)",
        "current_behaviour": "The bonus for shooting units on objectives is part of the rounds-4-5 "
                             "strategy block only. In rounds 1-3 an enemy unit on a marker is "
                             "valued the same as one in the open.",
        "suggested_change": "Move the objective-occupancy bonus out of the late-game block and "
                            "apply it whenever the active secondary or primary card pays for kills "
                            "on objectives — the SecondaryMissionManager hints already surface "
                            "this. Keep the extra late-game multiplier on top.",
        "risk": "Applied unconditionally it double-counts with the OC-denial value of the same "
                "kill and can pull fire off genuinely dangerous units early. Gate it on the "
                "mission actually paying for it.",
    },
    priority="medium",
)

add(
    decision="screening_and_zoning", faction="general",
    claim="A screen must still be intact during the opponent's turn, because Rapid Ingress "
          "lets reserves arrive in the opponent's Movement phase.",
    detail="Rapid Ingress moves a reserve unit onto the table during the opponent's movement "
           "phase, so a screen evaluated only at the end of the AI's own turn can be bypassed "
           "the moment it takes casualties or moves. Players build lists specifically around "
           "having a Rapid Ingress target and describe screening against it as a distinct "
           "obligation from screening against normal deep strike.",
    confidence="medium",
    evidence=[
        ev("40K Dirtbags", "Enm67qaqHkU", "04:00",
           "at least one unit in reserves cuz you're making lists to have a reserve rapid ingress target"),
        ev("WarGames Live", "1AwnDclFviQ", "159:00",
           "this dog is doing some rapid ingress screening which is nice ... Deep strike denying"),
        ev("Happy Krumping", "pAk1YiuioNQ", "57:00",
           "You don't have to screen the rapid ingress. You don't have to worry about screening"),
        ev("6 Plus Plus Gaming", "gRqdSBkqVlA", "06:00",
           "a big Helion Brick for rapid ingress threats ... I needed a infiltrate screen unit against things like Emperor's Children"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "new_heuristic",
        "target": "screening assignment validity window",
        "current_behaviour": "Screening positions are chosen during the AI's movement phase and "
                             "evaluated against the board as it stands then. Nothing re-checks "
                             "coverage after the AI's own shooting/charge phases move or lose the "
                             "screening unit.",
        "suggested_change": "Re-validate screening coverage at the end of the AI's turn and, when "
                            "a gap has opened, prefer keeping a screening unit stationary over "
                            "using it in a charge. Simplest form: mark units holding a screening "
                            "assignment as ineligible for charges unless the charge itself closes "
                            "the gap.",
        "risk": "Locking screeners out of charges wastes them when no reserves remain. Skip the "
                "restriction entirely once the opponent has nothing left in reserve — the AI can "
                "see reserve counts in the snapshot.",
    },
    priority="medium",
)

add(
    decision="positioning_and_concealment", faction="general",
    claim="Cover in 11e worsens the attacker's Ballistic Skill by 1 rather than improving the "
          "defender's save, so seeking cover degrades incoming fire and ignore-cover weapons "
          "are worth aiming deliberately.",
    detail="Benefit of Cover (13.08) applies a -1 to hit rather than a save bonus, which is a "
           "different shape of protection: it scales with the number of shots rather than with "
           "AP, and it stacks differently with re-rolls. Players call it out in play as 'your "
           "storm bolters will be at minus one to hit', and treat ignore-cover as a targeting "
           "consideration rather than a list-building nicety.",
    confidence="medium",
    evidence=[
        ev("Maelstrom Gaming Studios - Tyranids", "aQsog-fkQJ8", "85:00",
           "partially obscured ... your storm bolters will be at minus one to hit"),
        ev("TacticalTortoise 40k", "VqwMdS9MuIY", "171:00",
           "Don't get cover, right? Yeah. No, it's ignore cover for all"),
        ev("Play On Tabletop", "1SRkN4Drhs4", "52:00",
           "because you're not an infantry, so you have to be obscured by the terrain itself"),
    ],
    rules_status="confirmed",
    ai_impact={
        "seam": "weight_constant",
        "target": "movement destination scoring + EFFICIENCY_* target matching",
        "current_behaviour": "Cover terrain types are enumerated (COVER_TERRAIN_WITHIN_AND_BEHIND, "
                             "COVER_TERRAIN_WITHIN_ONLY) and RulesEngine resolves the modifier, but "
                             "movement scoring has no explicit term for ending in cover, and target "
                             "scoring has no term for the target being in cover.",
        "suggested_change": "Add a modest movement bonus for destinations granting Benefit of Cover "
                            "(smaller than the Hidden bonus in F001 — cover is a -1, Hidden is "
                            "immunity), and reduce a target's efficiency multiplier when it has "
                            "cover against the shooter unless the weapon ignores cover.",
        "risk": "Cover and Hidden are sought in the same terrain, so the two bonuses can "
                "double-count and over-concentrate the army into one ruin. Apply cover only when "
                "Hidden does not already apply.",
    },
    priority="medium",
)

add(
    decision="screening_and_zoning", faction="Tyranids",
    claim="Tyranids should spend cheap broods and spore mines as disposable movement blockers "
          "placed in the enemy's path, not as objective holders held back safely.",
    detail="Tyranid screening pieces are cheap enough to be spent every turn and are placed "
           "specifically to force the opponent to go around — the value is the movement tax, "
           "not the bodies. Players describe placing spore mines downfield turn after turn to "
           "close deep-strike lanes, and describe a single unscreened gap as what lets the "
           "opponent through.",
    differs_from_general="The general AI picks screeners by cost threshold and places them to "
                         "cover deep-strike arrival zones near its own objectives. Tyranids should "
                         "also project blockers forward into the enemy's approach lanes and treat "
                         "them as consumable each turn, which the general threat model would "
                         "penalise as walking into danger.",
    confidence="medium",
    evidence=[
        ev("Into the Hive Mind", "K8OD14Mz6N4", "09:00",
           "putting these spore mines out that screen out deep strikers or any kind of reserve"),
        ev("Grimdark Breakdown", "VPTL092E0VI", "13:00",
           "you could put things in their way to block their easy path"),
        ev("StrikingScorpion82", "sPWC5HujB_Y", "19:00",
           "holding objectives, picking on isolated, tying units down, blocking movements ... it's no big deal if they're slain"),
    ],
    rules_status="player_opinion",
    ai_impact={
        "seam": "profile_rule",
        "target": "CORRIDOR_BLOCK_SCORE_BASE (7.0) / CORRIDOR_BLOCK_MAX_POSITIONS (4)",
        "current_behaviour": "Corridor blocking exists at 7.0 base priority — below screening's "
                             "8.0 — capped at 4 positions, and requires an enemy within 30\" of the "
                             "objective being protected.",
        "suggested_change": "Tyranid profile: raise CORRIDOR_BLOCK_SCORE_BASE to ~9.0 so blocking "
                            "outbids screening for cheap broods, and raise "
                            "CORRIDOR_BLOCK_MAX_POSITIONS to 6. Lower THREAT_FRAGILE_BONUS so the "
                            "blockers accept being killed.",
        "risk": "Cheap Tyranid units are also the army's OC on objectives; spending them all as "
                "blockers can leave nothing scoring. Cap the number of units that may take a "
                "blocking assignment as a fraction of the army.",
    },
    priority="medium",
)

# --------------------------------------------------------------- disagreements
DISAGREEMENTS = [
    {
        "topic": "How much of the army to place in Strategic Reserves",
        "positions": [
            "Keep at least one unit in reserve as a reactive answer / Rapid Ingress threat "
            "(40K Dirtbags, Enm67qaqHkU 04:00; Art of War 40k, ym0SnzF2ydg 162:00)",
            "Against high-pressure lists put nothing in reserve — you need every body on the "
            "table to hold the mid-board (Happy Krumping, pAk1YiuioNQ 09:00)",
            "Reserves are unnecessary when the army has a redeploy ability instead "
            "(Deploy on the Line 40K, gZWxrJy66nw 12:00)",
        ],
        "note": "Not a contradiction so much as an unstated conditional: the resolving variable "
                "is the opponent's turn-one threat range, which the AI can compute. Encoded that "
                "way in F014 rather than picking a side.",
    },
    {
        "topic": "Whether the Disruption disposition is playable",
        "positions": [
            "Disruption scores poorly, which frees you to ignore scoring and just kill "
            "(Happy Krumping, pAk1YiuioNQ 70:00)",
            "Disruption sucks, people know it's awful (Deploy on the Line 40K, 14LSO7MS3QI 85:00)",
            "Disruption rewards movement and positioning and is about interfering with the "
            "opponent's plan (Warpbane Tactics, ogMKXBVh4g0 02:00)",
        ],
        "note": "Tournament data in the corpus (Warp Friends, PShNfK_IJAA 21:00) shows factions "
                "posting notably higher win rates INTO Disruption, supporting the 'weak "
                "disposition' read. The AI should not be tuned to Disruption as a baseline.",
    },
    {
        "topic": "Whether 11e Overwatch is oppressive or merely strong",
        "positions": [
            "You can't play around it any more — big squads just get overwatched "
            "(Deploy on the Line 40K, FT5JoL5Myis 05:00)",
            "It hits on sixes; it's not 'giga crazy' unless the volume is there "
            "(TacticalTortoise 40k, VqwMdS9MuIY 127:00)",
        ],
        "note": "Both are consistent with the rule: snap shooting punishes volume/torrent shooters "
                "and is weak for elite guns. The AI's exposure penalty should therefore scale with "
                "the watching unit's shot count, not its damage quality — reflected in F004.",
    },
    {
        "topic": "Whether World Eaters should still play maximum aggression in 11e",
        "positions": [
            "11e removed the need to push everything onto objectives; hold home, take a couple "
            "of bricks, do actions (Exile Wargaming, mbNWzDn6Pu4 34:00)",
            "The faction's identity and detachments remain melee-compulsion oriented "
            "(Tactical Sugar, uizU0NPlR14 10:00; WednesdayNightWarhammer, zVx7smZIRf0 04:00)",
        ],
        "note": "The corpus does not support FACTION_AGGRESSION_WORLD_EATERS = 2.0 as a "
                "well-evidenced value — it is the highest constant in the file and rests on no "
                "corpus evidence at all. Flagged in gaps rather than changed.",
    },
]

GAPS = [
    "Necrons (101 transcripts, 56 in-title) yielded no high-confidence differentiated finding. "
    "Coverage is heavy but almost entirely list-review and battle-report play-by-play; the "
    "reanimation-vs-trade reasoning the AI would need is never stated explicitly. This is the "
    "largest coverage-to-findings gap in the corpus.",
    "World Eaters (58 transcripts): only one channel makes a decision-shaped claim, and it "
    "argues AGAINST the blanket aggression the code already encodes. No profile emitted; "
    "FACTION_AGGRESSION_WORLD_EATERS = 2.0 should be treated as unevidenced.",
    "Leagues of Votann (47 transcripts, 16 in-title): the judgement-token search returned zero "
    "hits in the title-attributed pool. Either the mechanic changed in 11e or the corpus does "
    "not discuss it — unresolved.",
    "Aeldari (50), Thousand Sons (48), Chaos Knights (43), Emperor's Children (43): present in "
    "volume but discussion is list-composition and datasheet review, not decision reasoning. No "
    "actionable finding extracted.",
    "Adepta Sororitas (9), Agents of the Imperium (6), Ynnari (4), Harlequins (10): too thin to "
    "attribute anything safely.",
    "Imperial Knights and Chaos Knights: one channel notes they must pay CP to shoot and act in "
    "the same turn (Recon By Fire, 42CPnCfuCN8 01:00), which implies a distinctive action-economy "
    "problem for low-unit-count armies. Single-source, so recorded here rather than as a finding.",
    "The corpus is competitive/tournament-skewed and post-dates the late-July 2026 balance "
    "dataslate for only part of its range. Faction findings drawn on June/early-July material "
    "may already be stale; each finding's evidence dates are given so this can be re-checked.",
    "Deployment as a decision (where to place units before turn one) is discussed constantly but "
    "almost always in terms of a specific board and layout, which does not generalise into a "
    "weight. No deployment finding survived.",
    "Secondary mission selection and discard is barely reasoned about on camera despite being a "
    "per-turn decision the AI makes; the SECONDARY_* constants have no corpus support either way.",
]


def build():
    matrix = defaultdict(lambda: defaultdict(int))
    dcount = Counter()
    fcount = Counter()
    for f in F:
        matrix[f["decision"]][f["faction"]] += 1
        dcount[f["decision"]] += 1
        fcount[f["faction"]] += 1

    doc = {
        "generated": GENERATED,
        "corpus": CORPUS,
        "taxonomy": {
            "decisions": [
                {"name": k, "definition": v, "finding_count": dcount.get(k, 0)}
                for k, v in DECISIONS.items()
            ],
            "factions": [
                {"name": k, "transcript_count": FACTION_TRANSCRIPTS.get(k, 0),
                 "finding_count": fcount.get(k, 0)}
                for k in sorted(FACTION_TRANSCRIPTS,
                                key=lambda n: (-fcount.get(n, 0), -FACTION_TRANSCRIPTS[n]))
            ],
            "matrix": {d: dict(m) for d, m in matrix.items()},
        },
        "findings": F,
        "disagreements": DISAGREEMENTS,
        "gaps": GAPS,
    }
    with open(OUT, "w") as fh:
        json.dump(doc, fh, indent=2, ensure_ascii=False)
    print("wrote %s — %d findings, %d decisions, %d factions with findings"
          % (OUT, len(F), len(dcount), len(fcount)))
    return doc


if __name__ == "__main__":
    build()
