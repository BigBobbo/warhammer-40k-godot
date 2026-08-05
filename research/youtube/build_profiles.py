#!/usr/bin/env python3
"""Emit draft AI profiles in the ProfileManager format (40k/scripts/ProfileManager.gd).

These are DRAFTS FOR REVIEW, not tuned values. Every parameter and rule carries
the finding IDs that motivated it in the profile description, so a reviewer can
trace each number back to research/youtube/ai_learnings.json and from there to a
timestamped quote.

Two mechanics of the rule engine constrain what can be written here
(AIDecisionMaker.evaluate_rules / _apply_rule_actions / _get_base_param_value):

  * "multiply" and "add" actions resolve the base value from the profile's own
    `parameters` block or from ai_config.json overrides — NOT from the GDScript
    const. _get_base_param_value returns 0.0 when the parameter is absent, so a
    multiply against an undeclared parameter silently yields 0. Every parameter a
    rule multiplies is therefore declared in `parameters` at its current const
    value.
  * Rule conditions may only use the context keys the engine populates: phase,
    round, vp_diff, units_remaining_pct, nearest_enemy_inches, on_objective,
    is_melee_unit, is_vehicle, unit_points. Phase strings are the enum names
    (FORMATIONS, DEPLOYMENT, SCOUT, COMMAND, MOVEMENT, SHOOTING, CHARGE, FIGHT,
    SCORING).
"""

from __future__ import annotations

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "profiles")

PROFILES = [
    {
        "file": "orks.json",
        "profile_name": "Orks — Waaagh! discipline and Gretchin job-units (draft)",
        "description":
            "DRAFT from research/youtube/ai_learnings.json (corpus 2026-04..2026-08). "
            "F019 (Waaagh! timing, high confidence, 3 channels): the code at "
            "AIDecisionMaker.gd:4481 fires Waaagh! in round 1 on a single unit within 22\" "
            "and unconditionally from round 2. Players say the opposite — don't call it turn "
            "one, don't call it to reach one thing, want several units benefiting at once. "
            "WAAAGH_MIN_UNITS_IN_RANGE does not exist yet; it is declared here as the "
            "parameter the code change in F019 should read. "
            "F020 (Gretchin job-units, medium): SCREEN_CHEAP_UNIT_POINTS 100 -> 60 so only "
            "Gretchin-class units are screen candidates, SCREEN_SCORE_BASE 8.0 -> 10.0 so "
            "they take those jobs over a marginal objective push. "
            "FACTION_AGGRESSION_ORKS is left at the benchmark-tuned 1.2 "
            "(tests/bench_baselines/2026-07-10_ork_discipline_ab.md) — the corpus gives no "
            "reason to move a value that was settled by benchmark.",
        "parameters": {
            "FACTION_AGGRESSION_ORKS": 1.2,
            "WAAAGH_MIN_UNITS_IN_RANGE": 3,
            "SCREEN_CHEAP_UNIT_POINTS": 60,
            "SCREEN_SCORE_BASE": 10.0,
            "WEIGHT_ALREADY_HELD_OBJ": -3.0,
        },
        "rules": [
            {
                "id": "ork_waaagh_backstop",
                "name": "Waaagh! use-it-or-lose-it from round 4 (F019)",
                "priority": 10,
                "enabled": True,
                "conditions": [{"type": "phase", "value": "COMMAND"},
                               {"type": "round_gte", "value": 4}],
                "actions": [{"type": "override", "param": "WAAAGH_MIN_UNITS_IN_RANGE",
                             "value": 1}],
            },
            {
                "id": "ork_boyz_off_held_objectives",
                "name": "Melee units leave objectives already held — Gretchin hold them (F020)",
                "priority": 20,
                "enabled": True,
                "conditions": [{"type": "phase", "value": "MOVEMENT"},
                               {"type": "is_melee_unit"},
                               {"type": "on_objective"},
                               {"type": "unit_points_gte", "value": 150}],
                "actions": [{"type": "override", "param": "WEIGHT_ALREADY_HELD_OBJ",
                             "value": -7.0}],
            },
        ],
    },
    {
        "file": "adeptus_custodes.json",
        "profile_name": "Adeptus Custodes — concentrate, do not spread (draft)",
        "description":
            "DRAFT from research/youtube/ai_learnings.json. F022 (medium confidence, 3 "
            "channels): Custodes have too few units to screen and score at once; players "
            "describe the army as wanting to move as one wrecking ball and describe "
            "splitting as the mistake. The differentiating parameter is CONCENTRATION, not "
            "aggression — SUPPORT_STACK_PENALTY 3.5 -> 1.5 stops the AI pushing units apart, "
            "and WEIGHT_ALREADY_HELD_OBJ -3.0 -> -1.0 stops it abandoning ground it holds. "
            "FACTION_AGGRESSION_CUSTODES stays at 1.5: the corpus supports the army being "
            "fight-oriented, it does not support changing that number. "
            "This profile is the concrete argument that a single per-faction aggression "
            "scalar is too coarse — nothing about Custodes identity is expressible as "
            "'more or less aggressive'.",
        "parameters": {
            "FACTION_AGGRESSION_CUSTODES": 1.5,
            "SUPPORT_STACK_PENALTY": 1.5,
            "WEIGHT_ALREADY_HELD_OBJ": -1.0,
            "SCREEN_SCORE_BASE": 4.0,
        },
        "rules": [
            {
                "id": "custodes_late_spread",
                "name": "Rounds 4-5: allow spreading again for end-game objectives (F022)",
                "priority": 10,
                "enabled": True,
                "conditions": [{"type": "round_gte", "value": 4}],
                "actions": [
                    {"type": "override", "param": "SUPPORT_STACK_PENALTY", "value": 3.5},
                    {"type": "override", "param": "WEIGHT_ALREADY_HELD_OBJ", "value": -3.0},
                ],
            },
        ],
    },
    {
        "file": "tyranids.json",
        "profile_name": "Tyranids — forward shock delivery and disposable blockers (draft)",
        "description":
            "DRAFT from research/youtube/ai_learnings.json. F023 (medium, 4 channels): "
            "Tyranid battle-shock output is offensive tempo — shock a holder, strip its OC, "
            "then charge in and precision the character out. That means the aura carriers "
            "must be forward, so THREAT_FRAGILE_BONUS 1.3 -> 1.0 stops the AI treating them "
            "as things to hide. F031 (medium, 3 channels): cheap broods and spore mines are "
            "spent as movement blockers in the enemy's path, so CORRIDOR_BLOCK_SCORE_BASE "
            "7.0 -> 9.0 (above SCREEN_SCORE_BASE 8.0, so blocking outbids screening) and "
            "CORRIDOR_BLOCK_MAX_POSITIONS 4 -> 6. "
            "F009 (battle-shock OC denial) is a GENERAL finding and is deliberately NOT "
            "encoded here — it should land as core logic, not as a Tyranid quirk.",
        "parameters": {
            "THREAT_FRAGILE_BONUS": 1.0,
            "CORRIDOR_BLOCK_SCORE_BASE": 9.0,
            "CORRIDOR_BLOCK_MAX_POSITIONS": 6,
            "SCREEN_CHEAP_UNIT_POINTS": 120,
        },
        "rules": [
            {
                "id": "nids_protect_when_thin",
                "name": "Below 40% of the army, stop spending blockers (F031 risk note)",
                "priority": 10,
                "enabled": True,
                "conditions": [{"type": "units_remaining_pct_lte", "value": 40.0}],
                "actions": [
                    {"type": "override", "param": "CORRIDOR_BLOCK_SCORE_BASE", "value": 5.0},
                    {"type": "override", "param": "THREAT_FRAGILE_BONUS", "value": 1.3},
                ],
            },
        ],
    },
    {
        "file": "death_guard.json",
        "profile_name": "Death Guard — lock the enemy in, win by denial (draft)",
        "description":
            "DRAFT from research/youtube/ai_learnings.json. F024 (medium, 3 channels): "
            "Death Guard are described as low-damage and very hard to disengage from; the "
            "play is to engage and stay engaged so the enemy neither shoots nor scores, "
            "ideally with two units on one target so multiple fall-back tests are needed. "
            "PHASE_PLAN_LOCK_SHOOTER_BONUS 3.0 -> 5.0 makes lock-down charges compete, "
            "SURVIVAL_HOLD_BONUS 1.5 -> 3.0 and SURVIVAL_FALL_BACK_BONUS 2.0 -> 1.0 keep the "
            "AI in combats it is losing on damage. "
            "HIGHEST-RISK PROFILE IN THIS SET: staying in losing fights is exactly what "
            "survival assessment was added to prevent. Benchmark against a high-damage melee "
            "opponent before adopting anything here.",
        "parameters": {
            "PHASE_PLAN_LOCK_SHOOTER_BONUS": 5.0,
            "SURVIVAL_HOLD_BONUS": 3.0,
            "SURVIVAL_FALL_BACK_BONUS": 1.0,
            "PHASE_PLAN_RANGED_STRENGTH_DANGEROUS": 3.5,
        },
        "rules": [
            {
                "id": "dg_release_when_dying",
                "name": "Restore normal fall-back once the army is being ground down (F024 risk)",
                "priority": 10,
                "enabled": True,
                "conditions": [{"type": "units_remaining_pct_lte", "value": 50.0}],
                "actions": [
                    {"type": "override", "param": "SURVIVAL_FALL_BACK_BONUS", "value": 2.0},
                    {"type": "override", "param": "SURVIVAL_HOLD_BONUS", "value": 1.5},
                ],
            },
        ],
    },
    {
        "file": "drukhari.json",
        "profile_name": "Drukhari — expendable strike squads, transports as durability (draft)",
        "description":
            "DRAFT from research/youtube/ai_learnings.json. F025 (medium, 4 channels): "
            "Drukhari squads are sent to kill a key piece with no expectation of surviving, "
            "and leaving a squad outside its transport is named as the error. "
            "TRADE_UNFAVORABLE_PENALTY 0.7 -> 0.9 lets an expensive squad kill a cheaper key "
            "target, THREAT_FRAGILE_BONUS 1.3 -> 1.0 stops the AI refusing the exposure. "
            "The round-4 rule restores caution once trades stop buying anything. "
            "RISK: under a Purge the Foe opponent this profile feeds their primary directly "
            "— benchmark against Purge specifically.",
        "parameters": {
            "TRADE_UNFAVORABLE_PENALTY": 0.9,
            "THREAT_FRAGILE_BONUS": 1.0,
            "TRADE_FAVORABLE_BONUS": 1.3,
            "THREAT_CHARGE_PENALTY": 1.2,
        },
        "rules": [
            {
                "id": "drukhari_late_caution",
                "name": "Rounds 4-5: stop spending units, protect what scores (F025)",
                "priority": 10,
                "enabled": True,
                "conditions": [{"type": "round_gte", "value": 4}],
                "actions": [
                    {"type": "multiply", "param": "THREAT_FRAGILE_BONUS", "value": 1.3},
                    {"type": "override", "param": "TRADE_UNFAVORABLE_PENALTY", "value": 0.7},
                ],
            },
            {
                "id": "drukhari_commit_when_behind",
                "name": "Behind on VP: accept worse trades to break a stalemate (F025)",
                "priority": 20,
                "enabled": True,
                "conditions": [{"type": "vp_behind"}, {"type": "round_lte", "value": 3}],
                "actions": [{"type": "override", "param": "TRADE_UNFAVORABLE_PENALTY",
                             "value": 1.0}],
            },
        ],
    },
    {
        "file": "space_marines.json",
        "profile_name": "Space Marines — Oath valued by re-roll gain (draft)",
        "description":
            "DRAFT from research/youtube/ai_learnings.json. F026 (medium, 3 channels): "
            "Oath of Moment's value is the re-roll it ADDS, so it is wasted on a target our "
            "already-re-rolling units will shoot. The real fix is a code change in "
            "_select_oath_of_moment_target (AIDecisionMaker.gd:4844) to weight candidates by "
            "expected damage gained rather than by target properties — no existing constant "
            "expresses it, so OATH_REROLL_GAIN_WEIGHT is declared here as the parameter that "
            "change should read. "
            "This profile is therefore thinner than the others ON PURPOSE: the finding is a "
            "logic change, not a tuning change, and inventing constants to fake it would "
            "misrepresent the evidence.",
        "parameters": {
            "OATH_REROLL_GAIN_WEIGHT": 1.0,
            "MACRO_LEADER_BUFF_BONUS": 1.5,
        },
        "rules": [],
    },
]


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    for p in PROFILES:
        doc = {
            "format": "wh40k_ai_profile",
            "version": 1,
            "profile_name": p["profile_name"],
            "description": p["description"],
            "parameters": p["parameters"],
        }
        if p["rules"]:
            doc["rules"] = p["rules"]
        path = os.path.join(OUTDIR, p["file"])
        with open(path, "w") as fh:
            json.dump(doc, fh, indent="\t", ensure_ascii=False)
            fh.write("\n")
        print("wrote", path)


if __name__ == "__main__":
    main()
