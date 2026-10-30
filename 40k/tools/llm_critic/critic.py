#!/usr/bin/env python3
"""LLM critic — an LLM reviews the AI's suggestions while the AI plays itself.

The LLM never picks moves (legality stays with the engine). It reads what the
AI suggests at sampled decision points — the chosen option, the rejected ones,
every score term, the AI's own reasoning lines, the board — and judges whether
the LOGIC is flawed. Flagged decisions become loadable save files + AI test
cases; a final pass groups recurring flaws into improvement proposals for a
human to validate.

Stages (run all, or one at a time against an existing run dir):
  collect     seeded AI-vs-AI game(s) under PlanSimulator; at sampled decision
              points freeze (Engine.time_scale 0), capture the suggestion
              (capture.gd) + board (../llm_commander/snapshot.gd), save the
              position, unfreeze.                         [needs the game]
  review      one `claude -p` call per captured decision -> verdict JSON.
  synthesize  one `claude -p` call over the flagged reviews, with read access
              to the AI source, -> grouped improvement proposals.
  verify      reload each flagged position in a fresh game and check the AI
              still suggests the same thing (some drift)  [close the game first]
  report      REPORT.md; flagged positions get a "bad" test case + a copy in
              user://saves/ so they show up in the in-game Load menu.
  promote     copy reviewed case pairs into tests/ai_cases/ (after YOU agree).

Usage:
  python3 critic.py all --seeds 7001 --label first_look
  python3 critic.py collect --seeds 7001-7002 --army1 custodes_lions --army2 custodes_lions
  python3 critic.py review runs/<run>            # re-review with another model
  python3 critic.py report runs/<run>
  python3 critic.py promote runs/<run> <case_id> [...]

See README.md.
"""
import argparse
import base64
import io
import concurrent.futures as cf
import glob
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rules_context  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", ".."))  # 40k/
# The game's MCP bridge. Several critic games can run side by side: start each
# game with GODOT_MCP_PORT=<port> and this script with the same CRITIC_BRIDGE_PORT.
BRIDGE = ("127.0.0.1", int(os.environ.get("CRITIC_BRIDGE_PORT", "9080")))
USERDATA = os.path.expanduser(
    "~/Library/Application Support/Godot/app_userdata/40k" if sys.platform == "darwin"
    else "~/.local/share/godot/app_userdata/40k")

# GameState.Phase enum (verified live 2026-10-28)
PHASES = {"FORMATIONS": 0, "DEPLOYMENT": 1, "COMMAND": 6, "MOVEMENT": 7,
          "SHOOTING": 8, "CHARGE": 9, "FIGHT": 10}
DEFAULT_PHASES = "MOVEMENT,SHOOTING,CHARGE,FIGHT"

POLL_CODE = """var meta = GameState.state.get("meta", {})
return {"running": PlanSimulator.is_running(),
\t"round": int(meta.get("battle_round", 0)),
\t"phase": int(meta.get("phase", 0)),
\t"active": int(meta.get("active_player", 1)),
\t"actions": AIPlayer._action_log.size()}"""

# cancel() only stops the simulator WATCHING the game; the AI keeps playing it
# to the end unless stood down (both seats HUMAN, as between sim games).
CANCEL_CODE = "PlanSimulator.cancel()\nPlanSimulator._quiesce_ai()\nreturn true"


# ---------------------------------------------------------------- bridge

def call(command, params, timeout=180.0):
    s = socket.create_connection(BRIDGE, timeout=timeout)
    s.sendall((json.dumps({"id": 1, "command": command, "params": params}) + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    return json.loads(buf.decode().split("\n")[0]) if buf else {"error": "no response"}


def script(code, timeout=180.0):
    r = call("execute_script", {"code": code, "multiline": True}, timeout)
    res = r.get("result", {})
    if res.get("status") != "ok":
        raise RuntimeError(f"execute_script failed: {json.dumps(r)[:600]}")
    return res.get("result")


def load_gd(path):
    with open(path) as f:
        return "".join(l for l in f if not l.lstrip().startswith("#"))


def jdump(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, indent=1)


def read_jsonl(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [json.loads(l) for l in f if l.strip()]


# ---------------------------------------------------------------- collect

def collect(args, run_dir):
    capture_src = load_gd(os.path.join(HERE, "capture.gd"))
    roster_src = load_gd(os.path.join(HERE, "roster.gd"))
    terrain_src = load_gd(os.path.join(HERE, "terrain.gd"))
    mission_src = load_gd(os.path.join(HERE, "mission.gd"))
    prep_src = load_gd(os.path.join(HERE, "shot_prep.gd"))
    restore_src = load_gd(os.path.join(HERE, "shot_restore.gd"))
    snapshot_src = load_gd(os.path.join(HERE, "..", "llm_commander", "snapshot.gd"))
    phases = {PHASES[p.strip().upper()] for p in args.phases.split(",") if p.strip()}
    seats = {1, 2} if args.seat == 0 else {args.seat}
    run_name = os.path.basename(run_dir.rstrip("/"))
    user_dir = f"user://llm_critic/{run_name}/"
    bundles_path = os.path.join(run_dir, "bundles.jsonl")
    out = open(bundles_path, "a")
    n_total = 0
    for seed in parse_seeds(args.seeds):
        cfg = {"zone_id": args.zone, "layout_id": args.layout, "mission_id": args.mission,
               "army1": args.army1, "army2": args.army2, "games": 1, "seed_base": seed,
               "disposition1": args.disposition1, "disposition2": args.disposition2,
               "layout_variant": args.layout_variant,
               "difficulty": 3,  # Competitive: the AI plays the same tier the K card suggests at
               "time_scale": args.time_scale, "max_seconds_per_game": args.max_seconds}
        stop_previous_run()
        if not script(f"PlanSimulator.start({json.dumps(cfg)})\nreturn PlanSimulator.is_running()"):
            raise RuntimeError("PlanSimulator did not start (another run in progress?)")
        print(f"=== seed {seed}: {args.army1} vs {args.army2} ===", flush=True)
        roster = None
        seen = {}  # (round, active, phase) -> [captures, last_action_count]
        n_game = 0
        t0 = time.time()
        while True:
            p = script(POLL_CODE)
            if not p["running"]:
                break
            if p["round"] > args.max_round:
                script(CANCEL_CODE)
                print(f"  stopping after round {args.max_round}", flush=True)
                break
            key = (p["round"], p["active"], p["phase"])
            st = seen.setdefault(key, [0, -10**9])
            due = (p["phase"] in phases and st[0] < args.per_phase
                   and p["actions"] - st[1] >= args.stride and n_game < args.max_captures)
            if due:
                cid = f"s{seed}_r{p['round']}_p{p['active']}_{phase_name(p['phase']).lower()}_{st[0] + 1}"
                prev = script("var p := Engine.time_scale\nEngine.time_scale = 0.0\nreturn p")
                try:
                    if roster is None:
                        roster = script(roster_src)
                        jdump(os.path.join(run_dir, f"roster_s{seed}.json"), roster)
                        jdump(os.path.join(run_dir, f"terrain_s{seed}.json"), script(terrain_src))
                        jdump(os.path.join(run_dir, f"mission_s{seed}.json"), script(mission_src))
                    cap = script(capture_src.replace("__RUN_DIR__", user_dir).replace("__ID__", cid))
                    st[0] += 1
                    st[1] = p["actions"]
                    if cap.get("id") and int(cap.get("player", 0)) in seats:
                        cap["seed"] = seed
                        cap["board"] = script(snapshot_src)
                        if not args.no_shots:
                            cap["shots"] = take_shots(cid, run_dir, prep_src, restore_src)
                        out.write(json.dumps(cap) + "\n")
                        out.flush()
                        n_game += 1
                        print(f"  captured {cid}: {cap['suggestion'][:110]}", flush=True)
                    elif cap.get("error"):
                        print(f"  capture error {cid}: {cap['error']}", flush=True)
                finally:
                    # never restore a freeze (prev is 0 if something else froze the game)
                    script(f"Engine.time_scale = {prev if prev and prev > 0 else args.time_scale}\nreturn true")
            time.sleep(args.poll)
        n_total += n_game
        print(f"  seed {seed} done: {n_game} decisions captured in {time.time() - t0:.0f}s", flush=True)
    out.close()
    return n_total


def take_shots(cid, run_dir, prep_src, restore_src):
    """Two screenshots of the frozen game with the K-card board overlay drawn
    for this decision and the HUD hidden (shot_prep.gd): the whole board,
    cropped to the table, and a close-up of the actor, its targets and the
    chosen option's point. Saved as PNG under <run>/shots/. Returns
    {board, zoom, board_px_per_inch}: in the board image, pixel = inches *
    board_px_per_inch from the top-left corner, same axes as the board JSON."""
    from PIL import Image
    shots_dir = os.path.join(run_dir, "shots")
    os.makedirs(shots_dir, exist_ok=True)
    out = {}
    try:
        for mode in ("board", "zoom"):
            info = script(prep_src.replace("__MODE__", mode))
            if mode == "zoom" and not info.get("zoomed"):
                continue
            time.sleep(0.25)  # let a frame render with the new camera/overlay
            r = call("capture_screenshot", {})
            src = r.get("result", {}).get("absolute_path")
            if not src or not os.path.exists(src):
                print(f"  screenshot failed ({mode}): {json.dumps(r)[:200]}", flush=True)
                continue
            img = Image.open(src).convert("RGB")
            if mode == "board":
                x, y, w, h = info["board_rect"]
                img = img.crop((max(0, int(x)), max(0, int(y)),
                                min(img.width, int(x + w)), min(img.height, int(y + h))))
                out["board_px_per_inch"] = round(float(info["px_per_inch"]), 3)
            dest = os.path.join(shots_dir, f"{cid}_{mode}.png")
            img.save(dest)
            os.remove(src)
            out[mode] = os.path.relpath(dest, run_dir)
    finally:
        script(restore_src)
    return out


def stop_previous_run():
    """PlanSimulator.start() silently ignores a call while a run is in
    progress, and a run left frozen (time_scale 0, e.g. by an interrupted
    critic) never finishes its cancel. Unfreeze, cancel, wait it out."""
    if not script("return PlanSimulator.is_running()"):
        return
    print("  a PlanSimulator run is still in progress — cancelling it", flush=True)
    script("if Engine.time_scale <= 0.0:\n\tEngine.time_scale = 1.0\n" + CANCEL_CODE)
    for _ in range(120):
        if not script("return PlanSimulator.is_running()"):
            return
        time.sleep(1)
    raise RuntimeError("previous PlanSimulator run did not stop within 120s")


def phase_name(i):
    for k, v in PHASES.items():
        if v == i:
            return k
    return str(i)


def parse_seeds(s):
    if "-" in s:
        a, b = s.split("-")
        return list(range(int(a), int(b) + 1))
    return [int(x) for x in s.split(",")]


# ---------------------------------------------------------------- review

REVIEW_PREAMBLE = """You are an expert Warhammer 40,000 (11th edition) player reviewing \
the decision-making of a rules-based game AI. The engine already enforces legality — \
every option listed is legal. Your job is to judge the AI's JUDGEMENT: is the chosen \
option sensible given the board, and is the scoring logic that produced it flawed?

How the AI decides: for each decision it scores candidate options as a sum of named \
score terms (shown per option under "score_terms") and picks the highest score. Its \
own reasoning lines are under "ai_reasoning". Flaws you are looking for include: a \
term with the wrong sign or a wildly wrong magnitude; a term that double-counts \
another; a consideration the AI is missing entirely (e.g. an enemy threat, a unit's \
weapon range, a better target, an objective it could take for free, giving up a \
held objective); reasoning text that contradicts the numbers; plans that ignore \
round number / game end; wasting a unit's turn.

You get the full picture: screenshots of the board (attached images — look at them \
before judging), every terrain piece, line of sight from the acting unit to \
each enemy unit (computed by the engine), the board state and datasheets. Use the \
screenshots for what the numbers miss: terrain blocking a move or a firing lane, \
units bunched or isolated, screening, who can reach whom next turn. Screenshot \
legend: the AI's own suggestion overlay is drawn on top — cyan ring + \
"SUGGESTED" tag = the acting unit; red ring + "TARGET" tag + dashed line = its \
target(s); dashed arrows + translucent ghost bases = where a move would put the \
models; cyan "GOAL" marker = the point a move heads for. Objective markers are \
labelled (HOME 1, CENTER, NML 1...). Terrain: dark footprints are ruins / area \
terrain, walls are the dark strips inside them. Both armies may be the same \
faction — tell sides apart with the board JSON coordinates, not colours.

Board facts: coordinates are in inches; each player's home objective is \
obj_home_<player>. Objectives are controlled by the player with more total OC \
within range. "oc_p1/oc_p2" on each objective is current OC in range; "holder" is \
the current controller (0 = nobody). Units marked in_reserve are not on the board.

Be calibrated. "flawed" = a strong human player would clearly and confidently \
choose differently AND you can name the logic error. Close calls, reasonable \
alternatives and situations you lack information to judge are "questionable" or \
"sound". The 11th edition rules primer below covers the rules decisions usually hinge \
on, and the acting player's primary-mission table shows what objectives are \
actually worth. If a rule you need is not in the primer, look it up in the full \
core rules text with the Grep and Read tools (path given below) before \
answering. Use rules_uncertainty only for something the rules text genuinely \
does not settle, and say what you searched for.

Reply with ONLY one JSON object, no prose, no code fences. Write distances as \
"10 in", never with the " symbol:
{"verdict": "sound" | "questionable" | "flawed",
 "confidence": "low" | "medium" | "high",
 "severity": 0-3 (0 none, 1 minor inefficiency, 2 costs VP/units, 3 game-losing),
 "board_observations": "<1-2 sentences: what the screenshots show that matters here (terrain, \
lanes, who is near whom); write 'no screenshots' if none were attached>",
 "summary": "<one line: what the AI did and the problem, if any>",
 "better_option": "<the listed option text you would pick, or 'unlisted: ...', or '' if sound>",
 "logic_flaw": "<which score term(s) or missing consideration caused it, or ''>",
 "proposed_fix": "<a concrete, general heuristic change (not a one-off), or ''>",
 "rules_uncertainty": "<any rules you were unsure about, or ''>",
 "alternative": <null if sound, else your better option as ONE machine-readable action for the acting unit, \
using the exact unit ids (roster keys) and objective ids (as in the options), in one of these forms:
   {"kind": "move", "unit": "<acting unit id>", "objective": "<objective id>", "mode": "move" | "advance" | "hold"}
   {"kind": "shoot", "unit": "<acting unit id>", "target": "<enemy unit id>"}
   {"kind": "charge", "unit": "<acting unit id>", "targets": ["<enemy unit id>", ...]}   (targets [] = do not charge)
 Use null when your better option cannot be written this way.>}"""


STE = ("Write every text value in ASD-STE100 Simplified Technical English: "
       "short sentences (20 words or fewer), active voice, one statement per sentence, "
       "simple common words with one meaning each, no idioms or slang. "
       "Keep game terms (unit names, rule names, score term names) as they are.")

def build_review_prompt(bundle, roster, terrain=None, run_dir="", mission=None):
    me = int(bundle.get("player", 0))
    lines = [REVIEW_PREAMBLE, "", "== 11th edition rules primer ==", rules_context.primer(),
             f"Full core rules text (Grep/Read it for anything else): {rules_context.RULES_TEXT}", ""]
    if mission:
        mine = mission.get(str(me), {})
        theirs = mission.get(str(3 - me), {})
        lines += [f"== Primary mission scoring for Player {me} (the acting player; "
                  f"disposition {mine.get('disposition', '?')}) ==",
                  rules_context.primary_table(mine.get("card_id", "")) or "(card unknown)", "",
                  f"Opponent (Player {3 - me}) primary card: {theirs.get('card_name', '?')} — "
                  "denying their objectives lowers their score even when yours is capped.", ""]
    lines += [
             f"== Decision under review (Player {me}, round {bundle.get('round')}, {bundle.get('phase')} phase) ==",
             f"Suggestion: {bundle.get('suggestion')}",
             f"Decision type: {bundle.get('decision_type')}; acting unit: {bundle.get('unit_name')} ({bundle.get('unit_id')})",
             f"Decision context: {json.dumps(bundle.get('context', {}), separators=(',', ':'))}",
             f"Options (top {len(bundle.get('options', []))} of {bundle.get('options_total')}, best score first):"]
    for o in bundle.get("options", []):
        lines.append(json.dumps(o, separators=(",", ":")))
    lines += ["", "AI reasoning:"] + [f"  {s}" for s in bundle.get("ai_reasoning", [])[:40]]
    shots = bundle.get("shots", {})
    if shots.get("board") or shots.get("zoom"):
        lines += ["", "== Screenshots (attached above) =="]
        if shots.get("board"):
            lines.append(f"Image 1, whole board: pixel = board inches x {shots.get('board_px_per_inch')} "
                         "before any downscaling, origin top-left, same axes as the board JSON.")
        if shots.get("zoom"):
            lines.append(f"Image {2 if shots.get('board') else 1}: close-up of the decision.")
    if bundle.get("line_of_sight"):
        lines += ["", "== Line of sight from the acting unit (engine-computed, ignores range) =="]
        for l in bundle["line_of_sight"]:
            lines.append(json.dumps(l, separators=(",", ":")))
    lines += ["", "== Board ==", json.dumps(bundle.get("board", {}), separators=(",", ":"))]
    if terrain:
        lines += ["", "== Terrain (inches) =="] + [json.dumps(t, separators=(",", ":")) for t in terrain]
    if roster:
        lines += ["", "== Datasheets (unit id: line) =="]
        alive_ids = {u.get("id") for u in bundle.get("board", {}).get("units", []) if u.get("alive", 0) > 0}
        for uid, line in sorted(roster.items()):
            if uid in alive_ids:
                lines.append(f"{uid}: {line}")
    lines += ["", STE, "", "Review the decision now. JSON only."]
    return "\n".join(lines)


def _image_block(path):
    from PIL import Image
    img = Image.open(path).convert("RGB")
    img.thumbnail((1568, 1568))  # the API's useful maximum; larger is downscaled anyway
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=85)
    return {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg",
                                        "data": base64.b64encode(buf.getvalue()).decode()}}


def call_claude(prompt, model, timeout_s, read_code=False, images=(), rules_lookup=False):
    """`claude -p`. With images, they are sent INLINE as image blocks
    (stream-json input) — handing the model file paths to Read is not enough:
    measured 2026-10-28, the reviewer made zero tool calls and judged blind."""
    cmd = ["claude", "-p", "--model", model]
    if read_code:
        cmd += ["--allowedTools", "Read", "Grep", "Glob", "--add-dir", os.path.dirname(rules_context.RULES_TEXT)]
    elif rules_lookup:
        # the reviewer may look rules up in the core rules text (outside 40k/)
        cmd += ["--allowedTools", "Read", "Grep", "--add-dir", os.path.dirname(rules_context.RULES_TEXT)]
    stdin = prompt.encode()
    if images:
        cmd += ["--input-format", "stream-json", "--output-format", "stream-json", "--verbose"]
        content = [_image_block(p) for p in images] + [{"type": "text", "text": prompt}]
        stdin = (json.dumps({"type": "user", "message": {"role": "user", "content": content}}) + "\n").encode()
    t0 = time.time()
    try:
        proc = subprocess.run(cmd, input=stdin, capture_output=True,
                              timeout=timeout_s, cwd=PROJECT)
        out = proc.stdout.decode(errors="replace")
        if images:
            text = ""
            for line in out.splitlines():
                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if ev.get("type") == "result":
                    text = str(ev.get("result", ""))
            out = text
        return out, time.time() - t0, None
    except subprocess.TimeoutExpired:
        return "", time.time() - t0, "timeout"
    except Exception as e:  # noqa: BLE001 - report, never crash the run
        return "", time.time() - t0, f"{type(e).__name__}: {e}"


def parse_json_obj(raw):
    m = re.search(r"\{.*\}", raw, re.DOTALL)
    if not m:
        return None
    try:
        return json.loads(m.group(0))
    except json.JSONDecodeError:
        pass
    # Models write distances as 10" inside JSON strings; escape a quote that
    # follows a digit unless it closes a value (next char is , } ] or :).
    try:
        return json.loads(re.sub(r'(?<=\d)"(?!\s*[,}\]:])', r'\\"', m.group(0)))
    except json.JSONDecodeError:
        return None


def review(args, run_dir):
    bundles = read_jsonl(os.path.join(run_dir, "bundles.jsonl"))
    rosters = {}
    for p in glob.glob(os.path.join(run_dir, "roster_s*.json")):
        rosters[int(re.search(r"roster_s(\d+)", p).group(1))] = json.load(open(p))
    terrains = {}
    for p in glob.glob(os.path.join(run_dir, "terrain_s*.json")):
        terrains[int(re.search(r"terrain_s(\d+)", p).group(1))] = json.load(open(p))
    missions = {}
    for p in glob.glob(os.path.join(run_dir, "mission_s*.json")):
        missions[int(re.search(r"mission_s(\d+)", p).group(1))] = json.load(open(p))
    out_path = os.path.join(run_dir, "reviews.jsonl")
    # errored reviews are retried; --fresh redoes everything; --repeats N
    # reviews every decision N times independently (same inputs) to measure
    # how consistent the reviewer is.
    if args.fresh and os.path.exists(out_path):
        os.remove(out_path)
    have = {}
    for r in read_jsonl(out_path):
        if "error" not in r:
            have[r["id"]] = have.get(r["id"], 0) + 1
    todo = [b for b in bundles for _ in range(max(0, args.repeats - have.get(b["id"], 0)))]
    print(f"reviewing {len(todo)} decision(s) with {args.review_model} ({args.jobs} parallel, "
          f"{args.repeats} review(s) per decision)", flush=True)

    def one(b):
        prompt = build_review_prompt(b, rosters.get(b.get("seed")), terrains.get(b.get("seed")), run_dir,
                                     missions.get(b.get("seed")))
        shots = b.get("shots", {})
        imgs = [os.path.join(run_dir, shots[k]) for k in ("board", "zoom")
                if shots.get(k) and os.path.exists(os.path.join(run_dir, shots[k]))]
        raw, dt, err = call_claude(prompt, args.review_model, args.timeout, images=imgs, rules_lookup=True)
        rv = parse_json_obj(raw) if not err else None
        rec = {"id": b["id"], "model": args.review_model, "latency_s": round(dt, 1),
               "prompt_chars": len(prompt), "images": len(imgs)}
        if rv is None:
            rec.update({"error": err or "unparseable reply", "raw": raw[:800]})
        else:
            rec.update(rv)
        return rec

    with open(out_path, "a") as out, cf.ThreadPoolExecutor(args.jobs) as ex:
        for rec in ex.map(one, todo):
            out.write(json.dumps(rec) + "\n")
            out.flush()
            tag = rec.get("verdict", "ERROR").upper()
            print(f"  [{tag:12}] {rec['id']}: {rec.get('summary', rec.get('error', ''))[:120]}", flush=True)


# ---------------------------------------------------------------- synthesize

SYNTH_PREAMBLE = """You are improving a rules-based Warhammer 40,000 (11th edition) \
game AI written in GDScript (Godot 4). An expert reviewer has flagged the decisions \
below as flawed or questionable. You are running in the project root (the 40k/ \
folder) with read-only access: the decision logic lives mainly in \
scripts/AIDecisionMaker.gd (huge — use Grep for score term names such as the keys \
under score_terms, then Read around the hits) and autoloads/AIPlayer.gd.

Task:
1. Group the flags into distinct ROOT CAUSES (several flags often share one).
2. For each root cause, find where in the code the responsible score term or rule \
lives and propose a concrete, general change. Prefer small, targeted changes to \
existing terms over new systems. Reject flags you think the reviewer got wrong and \
say why — the reviewer can be mistaken.
3. Rank by expected impact on winning games.

Write Markdown (no preamble) with one section per root cause:
### <n>. <short title>  (impact: high|medium|low, confidence: high|medium|low)
- **Seen in:** case ids
- **What goes wrong:** ...
- **Where:** file:line / function / score term
- **Proposed change:** ...
- **How to verify:** which saved case(s) should change their choice, and what \
should NOT change.
Then a final section "### Reviewer flags I disagree with" (may be empty)."""


def synthesize(args, run_dir):
    bundles = {b["id"]: b for b in read_jsonl(os.path.join(run_dir, "bundles.jsonl"))}
    flagged = [r for r in read_jsonl(os.path.join(run_dir, "reviews.jsonl"))
               if r.get("verdict") in ("flawed", "questionable")]
    if not flagged:
        open(os.path.join(run_dir, "proposals.md"), "w").write("_No flawed or questionable decisions to synthesize._\n")
        print("nothing flagged — no proposals", flush=True)
        return
    lines = [SYNTH_PREAMBLE, "", "== 11th edition rules primer (the AI must follow these) ==",
             rules_context.primer(), f"Full core rules text: {rules_context.RULES_TEXT}", "",
             "== Flagged decisions =="]
    human = {}
    hpath = os.path.join(run_dir, "human_verdicts.json")
    if os.path.exists(hpath):
        human = json.load(open(hpath)).get("verdicts", {})
    for r in flagged:
        b = bundles.get(r["id"], {})
        lines.append(json.dumps({
            "case": r["id"], "verdict": r.get("verdict"), "confidence": r.get("confidence"),
            "severity": r.get("severity"), "phase": b.get("phase"), "round": b.get("round"),
            "suggestion": b.get("suggestion"), "decision_type": b.get("decision_type"),
            "options": b.get("options", [])[:4],
            "review": {k: r.get(k) for k in ("summary", "better_option", "logic_flaw", "proposed_fix", "rules_uncertainty")},
            "human": human.get(r["id"], {}),
        }, separators=(",", ":")))
    if human:
        lines += ["", "== Human reviewer feedback (AUTHORITATIVE: it overrides the LLM reviewer; "
                  "address every note in your proposals) =="]
        for cid, v in sorted(human.items()):
            if v.get("note") or v.get("ai") or v.get("critic"):
                lines.append(json.dumps({"case": cid, **v}, separators=(",", ":")))
    print(f"synthesizing {len(flagged)} flag(s) with {args.synth_model} (reads AI source)...", flush=True)
    lines += ["", STE]
    raw, dt, err = call_claude("\n".join(lines), args.synth_model, args.synth_timeout, read_code=True)
    text = raw.strip() if not err else f"_Synthesis failed: {err}_\n"
    open(os.path.join(run_dir, "proposals.md"), "w").write(text + "\n")
    print(f"  proposals.md written ({dt:.0f}s)", flush=True)


# ---------------------------------------------------------------- report

SEV = {"flawed": 0, "questionable": 1, "sound": 2}


def user_path(user_dir_name, fname):
    return os.path.join(USERDATA, "llm_critic", user_dir_name, fname)


def report(args, run_dir):
    run_name = os.path.basename(run_dir.rstrip("/"))
    bundles = {b["id"]: b for b in read_jsonl(os.path.join(run_dir, "bundles.jsonl"))}
    reviews = read_jsonl(os.path.join(run_dir, "reviews.jsonl"))
    by_id = {}
    for r in reviews:
        by_id.setdefault(r["id"], []).append(r)
    latest = {}
    for cid, rs in by_id.items():
        ok = [r for r in rs if "verdict" in r] or rs
        # the card leads with the majority verdict (ties: the most severe)
        tally = {}
        for r in ok:
            tally[r.get("verdict")] = tally.get(r.get("verdict"), 0) + 1
        top = max(tally, key=lambda v: (tally[v], -SEV.get(v, 3)))
        latest[cid] = [r for r in ok if r.get("verdict") == top][-1]
    rows = sorted(latest.values(), key=lambda r: (SEV.get(r.get("verdict"), 3), -int(r.get("severity") or 0)))
    counts = {}
    for r in rows:
        counts[r.get("verdict", "error")] = counts.get(r.get("verdict", "error"), 0) + 1
    saves_dir = os.path.join(USERDATA, "saves")
    os.makedirs(saves_dir, exist_ok=True)
    md = [f"# LLM critic report — {run_name}", "",
          f"Decisions reviewed: {len(rows)} — " + ", ".join(f"{k}: {v}" for k, v in sorted(counts.items())), "",
          "Flagged positions are saved as `llm_critic_<case>` in the in-game **Load** menu: load one, press **K**, "
          "and check the AI's card against the review. Agree → "
          f"`python3 40k/tools/llm_critic/critic.py promote {os.path.relpath(run_dir, os.path.dirname(PROJECT))} <case>` "
          "turns it into a regression case in `40k/tests/ai_cases/` (FAILS until the AI is fixed).", ""]
    prop = os.path.join(run_dir, "proposals.md")
    if os.path.exists(prop):
        md += ["## Proposed improvements (grouped by root cause)", "", open(prop).read().strip(), ""]
    vpath = os.path.join(run_dir, "verify.json")
    repro = json.load(open(vpath)) if os.path.exists(vpath) else {}
    md += ["## Per-decision reviews", "",
           "Repro = the position reloads to the same AI suggestion (`critic.py verify`); "
           "only promote cases marked yes.", "",
           "| Verdict | Sev | Conf | Repro | Case | AI suggested | Problem |", "|---|---|---|---|---|---|---|"]
    for r in rows:
        b = bundles.get(r["id"], {})
        rv = repro.get(r["id"])
        rp = ("yes" if (rv.get("same") if isinstance(rv, dict) else rv) else "no") if r["id"] in repro else ""
        md.append("| {} | {} | {} | {} | `{}` | {} | {} |".format(
            r.get("verdict", "ERROR"), r.get("severity", ""), r.get("confidence", ""), rp, r["id"],
            cell(b.get("suggestion", "")), cell(r.get("summary", r.get("error", "")))))
    md += [""]
    for r in rows:
        if r.get("verdict") not in ("flawed", "questionable"):
            continue
        b = bundles.get(r["id"], {})
        md += [f"### `{r['id']}` — {r.get('verdict')} (severity {r.get('severity')}, {r.get('confidence')} confidence)",
               f"- **AI suggested:** {b.get('suggestion', '')}",
               f"- **Problem:** {r.get('summary', '')}",
               f"- **Better option:** {r.get('better_option', '')}",
               f"- **Logic flaw:** {r.get('logic_flaw', '')}",
               f"- **Proposed fix:** {r.get('proposed_fix', '')}"]
        if r.get("rules_uncertainty"):
            md.append(f"- **Rules uncertainty:** {r['rules_uncertainty']}")
        md.append("- **Options the AI weighed:** " + "; ".join(
            f"{'**' if o.get('chosen') else ''}{o.get('option')} ({o.get('score')}){'**' if o.get('chosen') else ''}"
            for o in b.get("options", [])[:5]))
        md.append("")
        # Mark the pending case "bad" with the critic's note, and expose the
        # position in the Load menu.
        cj = user_path(run_name, r["id"] + ".json")
        if os.path.exists(cj):
            case = json.load(open(cj))
            case["verdict"] = "bad" if r.get("verdict") == "flawed" else "pending"
            case["note"] = f"[LLM critic, {r.get('confidence')} conf] {r.get('summary', '')} Fix: {r.get('proposed_fix', '')}"[:600]
            jdump(cj, case)
            sv = user_path(run_name, r["id"] + ".w40ksave")
            if os.path.exists(sv):
                shutil.copy(sv, os.path.join(saves_dir, f"llm_critic_{r['id']}.w40ksave"))
    path = os.path.join(run_dir, "REPORT.md")
    open(path, "w").write("\n".join(md) + "\n")
    print(f"report: {path}", flush=True)
    import html_report
    open(os.path.join(run_dir, "REPORT.artifact.html"), "w").write(html_report.build(
        run_dir, bundles, rows, repro, open(prop).read() if os.path.exists(prop) else "", by_id, standalone=False))
    hpath = os.path.join(run_dir, "REPORT.html")
    open(hpath, "w").write(html_report.build(run_dir, bundles, rows, repro,
                                             open(prop).read() if os.path.exists(prop) else "", by_id))
    print(f"html report: {hpath}", flush=True)
    return path


def cell(s):
    return str(s).replace("|", "/").replace("\n", " ")[:160]


def verify(args, run_dir):
    """Reload each flagged position in a fresh game (tests/run_ai_test_cases.sh,
    one windowed scenario per case) and record whether the AI still makes the
    same suggestion. Some in-phase state (e.g. the shooting order) is not in a
    save, so a few positions drift on reload — those are poor regression cases
    and the report says so. Launches its own game: close the running one."""
    run_name = os.path.basename(run_dir.rstrip("/"))
    flagged = [r["id"] for r in read_jsonl(os.path.join(run_dir, "reviews.jsonl"))
               if r.get("verdict") in ("flawed", "questionable")]
    cases = [user_path(run_name, cid + ".json") for cid in dict.fromkeys(flagged)]
    cases = [c for c in cases if os.path.exists(c)]
    if not cases:
        print("no flagged cases to verify", flush=True)
        return
    print(f"reloading {len(cases)} flagged position(s) to check they reproduce...", flush=True)
    proc = subprocess.run(["bash", "tests/run_ai_test_cases.sh"] + cases, cwd=PROJECT,
                          capture_output=True, timeout=args.verify_timeout)
    # the runner's structured per-case results (what the AI picks on reload)
    rpath = os.path.join(USERDATA, "ai_case_results_current.json")
    raw = json.load(open(rpath)) if os.path.exists(rpath) else {}
    res = {}
    for sid, r in raw.items():
        cid = sid[len("ai_case_"):] if sid.startswith("ai_case_") else sid
        if cid in flagged and "same" in r:
            res[cid] = {"same": bool(r["same"]), "now": r.get("now_description", ""),
                        "now_options": r.get("now_options", [])}
    jdump(os.path.join(run_dir, "verify.json"), res)
    for cid in dict.fromkeys(flagged):
        v = res.get(cid)
        print(f"  {cid}: " + ("not checked" if v is None else "reproduces" if v["same"]
                             else f"DRIFTS on reload -> {v['now'][:90]}"), flush=True)


def value(args, run_dir):
    """Value check: turn each flagged review's machine-readable "alternative"
    into a counterfactual rollout job (tools/ai_lab/rollout.py: the AI's choice
    vs the alternative from the saved position, paired seeds, short horizon)
    and, with --value-run, run the jobs here. Jobs go to value_jobs.json so a
    driver can also shard them across machines."""
    run_name = os.path.basename(run_dir.rstrip("/"))
    jobs, seen = [], set()
    for r in read_jsonl(os.path.join(run_dir, "reviews.jsonl")):
        if r.get("verdict") not in ("flawed", "questionable"):
            continue
        alt = r.get("alternative")
        if not isinstance(alt, dict) or alt.get("kind") not in ("move", "shoot", "charge"):
            continue
        case = user_path(run_name, r["id"] + ".json")
        if not os.path.exists(case):
            continue
        key = (r["id"], json.dumps(alt, sort_keys=True))
        if key in seen:
            continue
        seen.add(key)
        jobs.append({"id": r["id"], "job": "%s_%d" % (r["id"], len(jobs)), "case": case, "alt": [alt],
                     "verdict": r.get("verdict"), "severity": r.get("severity"),
                     "summary": r.get("summary", ""), "better_option": r.get("better_option", "")})
    jdump(os.path.join(run_dir, "value_jobs.json"), jobs)
    print(f"{len(jobs)} value job(s) -> {os.path.join(run_dir, 'value_jobs.json')}", flush=True)
    if not args.value_run:
        return
    out_dir = os.path.join(run_dir, "values")
    os.makedirs(out_dir, exist_ok=True)
    rollout = os.path.join(PROJECT, "..", "tools", "ai_lab", "rollout.py")
    for j in jobs:
        out = os.path.join(out_dir, j["job"] + ".json")
        if os.path.exists(out):
            continue
        subprocess.run([sys.executable, rollout, "run", "--case", j["case"], "--alt", json.dumps(j["alt"]),
                        "--seeds", str(args.value_seeds), "--horizon", str(args.value_horizon),
                        "--lanes", str(args.value_lanes), "--tag", run_name + "_" + j["job"], "--out", out])
    for j in jobs:
        out = os.path.join(out_dir, j["job"] + ".json")
        if os.path.exists(out):
            v = json.load(open(out)).get("effect_value", {})
            print(f"  {j['job']}: E {v.get('mean')} VP (se {v.get('se')}, 95% {v.get('ci95')}) — {j['better_option'][:70]}")


def promote(args, run_dir):
    run_name = os.path.basename(run_dir.rstrip("/"))
    dest = os.path.join(PROJECT, "tests", "ai_cases")
    if args.from_verdicts:
        promote_from_verdicts(args, run_dir, run_name, dest)
        return
    for cid in args.cases:
        cj = user_path(run_name, cid + ".json")
        if not os.path.exists(cj):
            print(f"  no case {cid} ({cj})")
            continue
        case = json.load(open(cj))
        if case.get("verdict") not in ("good", "bad"):
            case["verdict"] = args.verdict
            jdump(cj, case)
        shutil.copy(cj, os.path.join(dest, cid + ".json"))
        shutil.copy(user_path(run_name, case["save_file"]), os.path.join(dest, case["save_file"]))
        print(f"  promoted {cid} ({case['verdict']}) -> tests/ai_cases/")


def promote_from_verdicts(args, run_dir, run_name, dest):
    """Verdicts exported from REPORT.html: every decision you called good or
    bad becomes a test case with YOUR verdict (good locks the choice in, bad
    fails until the AI changes it), your note first. Also scores the reviewer."""
    data = json.load(sys.stdin if args.from_verdicts == "-" else open(args.from_verdicts))
    verdicts = data.get("verdicts", {})
    reviews = {r["id"]: r for r in read_jsonl(os.path.join(run_dir, "reviews.jsonl"))}
    right = wrong = 0
    for cid, v in sorted(verdicts.items()):
        if v.get("critic") == "right":
            right += 1
        elif v.get("critic") == "wrong":
            wrong += 1
        if v.get("ai") not in ("good", "bad"):
            continue
        cj = user_path(run_name, cid + ".json")
        if not os.path.exists(cj):
            print(f"  no case {cid} ({cj})")
            continue
        case = json.load(open(cj))
        r = reviews.get(cid, {})
        case["verdict"] = v["ai"]
        case["note"] = (v.get("note", "").strip() + (" | " if v.get("note") else "") +
                        f"[LLM critic said {r.get('verdict')}: {r.get('summary', '')}]")[:800]
        jdump(cj, case)
        shutil.copy(cj, os.path.join(dest, cid + ".json"))
        shutil.copy(user_path(run_name, case["save_file"]), os.path.join(dest, case["save_file"]))
        print(f"  promoted {cid} ({v['ai']}) -> tests/ai_cases/")
    if right + wrong:
        print(f"reviewer accuracy (your judgement): {right}/{right + wrong} right")
    jdump(os.path.join(run_dir, "human_verdicts.json"), data)


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("stage", choices=["all", "collect", "review", "synthesize", "report", "verify", "promote", "value"])
    ap.add_argument("run_dir", nargs="?", help="existing run dir (all stages but collect/all)")
    ap.add_argument("cases", nargs="*", help="promote: case ids")
    g = ap.add_argument_group("collect")
    g.add_argument("--seeds", default="7001")
    g.add_argument("--label", default="run")
    g.add_argument("--army1", default="custodes_lions")
    g.add_argument("--army2", default="custodes_lions")
    g.add_argument("--zone", default="hammer_anvil")
    g.add_argument("--layout", default="take_and_hold_mirror_1")
    g.add_argument("--mission", default="take_and_hold")
    g.add_argument("--disposition1", default="", help="11e Force Disposition for P1 ('' = take_and_hold)")
    g.add_argument("--disposition2", default="", help="11e Force Disposition for P2")
    g.add_argument("--layout-variant", type=int, default=1, help="with both dispositions and --layout '': official layout variant 1-3")
    g.add_argument("--seat", type=int, default=0, choices=[0, 1, 2], help="review only this player's decisions (0 = both)")
    g.add_argument("--phases", default=DEFAULT_PHASES, help="comma list of " + ",".join(PHASES))
    g.add_argument("--per-phase", type=int, default=2, help="max captures per player-phase")
    g.add_argument("--stride", type=int, default=2, help="min AI actions between captures in one phase")
    g.add_argument("--max-captures", type=int, default=40, help="per game")
    g.add_argument("--max-round", type=int, default=5)
    g.add_argument("--time-scale", type=float, default=2.0)
    g.add_argument("--max-seconds", type=float, default=1800.0)
    g.add_argument("--poll", type=float, default=0.3)
    g.add_argument("--no-shots", action="store_true", help="skip screenshots (faster, blind reviewer)")
    g = ap.add_argument_group("review / synthesize")
    g.add_argument("--review-model", default="claude-sonnet-5-5")
    g.add_argument("--synth-model", default="claude-opus-5-5")
    g.add_argument("--jobs", type=int, default=4)
    g.add_argument("--timeout", type=float, default=180)
    g.add_argument("--synth-timeout", type=float, default=900)
    g.add_argument("--fresh", action="store_true", help="review: discard earlier reviews")
    g.add_argument("--repeats", type=int, default=1, help="review: independent reviews per decision (consistency check)")
    g.add_argument("--no-synth", action="store_true")
    g.add_argument("--verify-timeout", type=float, default=1800)
    g.add_argument("--from-verdicts", help="promote: verdicts JSON copied from REPORT.html (- = stdin)")
    g.add_argument("--verdict", default="bad", choices=["bad", "good"], help="promote: verdict for still-pending cases")
    g = ap.add_argument_group("value (counterfactual rollouts of each flagged alternative)")
    g.add_argument("--value-run", action="store_true", help="run the rollout jobs here (else only write value_jobs.json)")
    g.add_argument("--value-seeds", type=int, default=12)
    g.add_argument("--value-horizon", type=int, default=1, help="rounds after the decision round; 0 = full game")
    g.add_argument("--value-lanes", type=int, default=4)
    args = ap.parse_args()

    if args.stage in ("all", "collect"):
        run_dir = os.path.join(HERE, "runs", time.strftime("%Y%m%d_%H%M%S") + "_" + args.label)
        os.makedirs(run_dir, exist_ok=True)
        jdump(os.path.join(run_dir, "config.json"), vars(args))
        print(f"run dir: {run_dir}", flush=True)
        n = collect(args, run_dir)
        if args.stage == "collect" or n == 0:
            print(f"collected {n} decision(s)")
            return
    else:
        if not args.run_dir:
            ap.error("run_dir is required for this stage")
        run_dir = os.path.abspath(args.run_dir)
    if args.stage in ("all", "review"):
        review(args, run_dir)
    if args.stage in ("all", "synthesize") and not args.no_synth:
        synthesize(args, run_dir)
    if args.stage in ("all", "review", "synthesize", "report"):
        report(args, run_dir)
    if args.stage == "verify":
        verify(args, run_dir)
        report(args, run_dir)
    if args.stage == "promote":
        promote(args, run_dir)
    if args.stage == "value":
        value(args, run_dir)


if __name__ == "__main__":
    main()
