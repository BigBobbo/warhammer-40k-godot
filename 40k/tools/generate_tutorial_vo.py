#!/usr/bin/env python3
"""Generate the Ork-voiced tutorial voiceover clips.

Offline asset generator — it never runs inside the game. It reads the lesson
files under data/tutorials/lessons/, turns each step's prompt into speakable
text, synthesises it with Piper (a local neural TTS — no cloud, no API key,
no per-word cost), runs the result through a SoX "ork" chain, and writes one
Ogg Vorbis clip per step into assets/audio/vo/tutorial/.

At runtime autoloads/TutorialVoice.gd reads data/tutorials/vo_manifest.json and
plays the clip for whichever step the card is showing.

    # one-time host setup (Debian/Ubuntu; see docs/TUTORIAL_VOICEOVER.md)
    apt-get install -y sox ffmpeg
    pip3 install piper-tts
    python3 -m piper.download_voices --download-dir ~/piper-voices \
        en_GB-northern_english_male-medium

    # regenerate everything that changed
    python3 40k/tools/generate_tutorial_vo.py

    # audition the voice on one line without touching the assets
    python3 40k/tools/generate_tutorial_vo.py --say "OI! Move da boyz!"

Why this voice: Orks are written with broad working-class northern-English
accents, so `en_GB-northern_english_male` starts in the right place and the
DSP chain only has to add the size and the gravel — pitched down 3.5 semitones,
chest and throat EQ, a little overdrive rasp, and a small scrapyard room. The
chain is deliberately restrained: this is a TUTORIAL, so intelligibility beats
character every time. `--ork-intensity` trades one for the other.

Generation is incremental — the manifest stores a hash of the speakable text
and the voice settings per clip, so an unchanged step is skipped.
"""
import argparse
import concurrent.futures
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.normpath(os.path.join(HERE, ".."))
LESSON_DIR = os.path.join(PROJECT, "data", "tutorials", "lessons")
TOKENS_PATH = os.path.join(PROJECT, "data", "tutorials", "vo_tokens.json")
MANIFEST_PATH = os.path.join(PROJECT, "data", "tutorials", "vo_manifest.json")
OUT_DIR = os.path.join(PROJECT, "assets", "audio", "vo", "tutorial")

DEFAULT_VOICE = os.path.expanduser("~/piper-voices/en_GB-northern_english_male-medium.onnx")

# Piper knobs. length_scale > 1 slows delivery (an Ork is not in a hurry and a
# learner needs the beat); noise_w adds a little articulation wobble.
PIPER_LENGTH_SCALE = 1.06
PIPER_NOISE_SCALE = 0.60
PIPER_NOISE_W = 0.85
SENTENCE_SILENCE = 0.35

# Bump when the pipeline changes in a way that should invalidate every clip.
PIPELINE_VERSION = 1


# --------------------------------------------------------------------------
# Speakable-text normalisation
# --------------------------------------------------------------------------

# BBCode the card renders as formatting — the tags go, the words stay. Any
# OTHER bracketed run (e.g. "[Escape]", "[Embarked]") is real on-screen text,
# so only its brackets are dropped.
BBCODE_TAGS = (
    "b", "i", "u", "s", "code", "center", "right", "fill", "indent",
    "url", "img", "color", "bgcolor", "fgcolor", "font", "font_size",
    "outline_size", "outline_color", "p", "left", "wave", "shake", "fade",
)
BBCODE_RE = re.compile(r"\[/?(?:%s)(?:=[^\]]*)?\]" % "|".join(BBCODE_TAGS), re.IGNORECASE)

# Pad glyph id -> how a voice should say it. The glyph TABLE (a -> "A") comes
# from the game via vo_tokens.json; this maps the resulting label to speech, so
# a remapped or PlayStation-style layout still reads correctly.
GLYPH_SPEECH = {
    "A": "the A button", "B": "the B button", "X": "the X button", "Y": "the Y button",
    "LB": "the left bumper", "RB": "the right bumper",
    "LT": "the left trigger", "RT": "the right trigger",
    "LS": "the left stick", "RS": "the right stick",
    "L3": "the left stick click", "R3": "the right stick click",
    "L4": "the left back paddle", "R4": "the right back paddle",
    "✚": "the D pad", "☰": "the Menu button", "⧉": "the View button",
}

# Keyboard display names -> speech. "Shift+/" has to become words or the
# phonemizer spells punctuation, and "W / Up" reads as a division sum.
KEY_SYMBOL_SPEECH = {
    "/": "forward slash", "\\": "backslash", "[": "left bracket", "]": "right bracket",
    "-": "minus", "=": "equals", ",": "comma", ".": "full stop", ";": "semicolon",
    "'": "apostrophe", "`": "backtick", "Space": "Spacebar", "Escape": "Escape",
}

# Symbols that appear in prompt text and must not reach the phonemizer raw.
SYMBOL_SPEECH = {
    "—": ", ", "–": ", ", "→": " then ", "⏩": " fast forward ",
    "▲": " up ", "▼": " down ", "◀": " left ", "▶": " right ",
    "●": " ", "⚄": " dice ", "✔": " tick ", "°": " degrees ",
    "&": " and ", "%": " percent ", "…": ", ", "+": " plus ",
}

# Apostrophe forms, mapped BEFORE the bare apostrophes are stripped — "an'"
# has to become "and" without the article "an" being caught by the same rule,
# and a dropped leading H ("'appens") is unreadable once the mark is gone.
ORK_APOSTROPHE = {
    "an'": "and", "'em": "them", "'ere": "here", "'ard": "hard", "'eads": "heads",
    "'ead": "head", "'appens": "happens", "'appen": "happen", "'avin": "having",
    "'ave": "have", "'as": "has", "'im": "him", "'is": "his", "'ole": "hole",
    "'ammer": "hammer", "'and": "hand", "'igh": "high", "'urt": "hurt",
    "you's": "youse", "dat's": "dhats", "it's": "its", "nothing's": "nothings",
}

# Ork dialect the phonemizer gets wrong, respelled so it comes out right. This
# is a PRONUNCIATION map, not a translation — the Ork voice keeps its accent,
# it just stops mispronouncing itself. Applied whole-word, case-insensitive.
# Entries are only worth adding when the default reading is actually wrong;
# `--say` plus the ASR check in tests/test_tutorial_vo.py is how that is judged.
ORK_PRONUNCIATION = {
    "da": "duh",          # otherwise leans toward "dar", then "dark" before a K
    "dat": "dhat",
    "dats": "dhats",
    "dem": "dhem",
    "den": "dhen",
    "dey": "dhey",
    "dis": "dhis",
    "wiv": "with",        # "wiv" phonemizes as "wive"
    "yer": "yur",
    "ya": "yah",
    "sez": "says",
    "trukk": "truck",
    "fings": "things",
    "fing": "thing",
    "everyfing": "everything",
    "somefing": "something",
    "nuffin": "nothing",
    "wot": "what",
    "propa": "propper",
    "proppa": "propper",
    "togevver": "togever",
}

DICE_RE = re.compile(r"\b(\d*)[Dd](\d+)\b")
INCHES_RE = re.compile(r'(\d+(?:\.\d+)?)\s*["″]')
NUMBER_WORDS = {
    "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four",
    "5": "five", "6": "six", "7": "seven", "8": "eight", "9": "nine",
}


# Wraps an expanded {key:...} so a RUN of them ("{key:up} {key:left} …") can be
# comma-joined afterwards; four key names in a row read as one garbled word.
KEY_MARK = "\x01"


def _speak_key(display: str) -> str:
    """'Ctrl+A' -> 'Control A'; 'W / Up' -> 'W'; 'Shift+/' -> 'Shift forward slash'.

    Only the PRIMARY binding is spoken. The alternate ("W / Up") is there to be
    read off the card at a glance; saying both turns a four-key list into a
    sixteen-word mouthful.
    """
    primary = display.split(" / ")[0].strip()
    parts = [p.strip() for p in primary.split("+") if p.strip()]
    spoken = [KEY_SYMBOL_SPEECH.get(p, {"Ctrl": "Control"}.get(p, p)) for p in parts]
    return " ".join(spoken)


def _speak_token(kind: str, arg: str, tokens: dict) -> str:
    if kind == "key":
        display = tokens.get("keys", {}).get(arg)
        if display is None:
            raise KeyError("no keybinding in vo_tokens.json for '%s' — re-run "
                           "tools/dump_vo_tokens.gd" % arg)
        return "%s%s%s" % (KEY_MARK, _speak_key(display), KEY_MARK)
    if kind == "hint":
        # A hint chip is "<glyph> <live label>"; the label is runtime state the
        # generator cannot know, so speak the button and let the card show the rest.
        kind, arg = arg, ""
    label = tokens.get("glyphs", {}).get(kind)
    if label is None:
        raise KeyError("no glyph in vo_tokens.json for '%s' — re-run "
                       "tools/dump_vo_tokens.gd" % kind)
    return " %s " % GLYPH_SPEECH.get(label, "the %s button" % label)


TOKEN_RE = re.compile(r"\{([a-zA-Z0-9_]+?)(?::([a-zA-Z0-9_]+))?\}")
KEY_RUN_RE = re.compile(r"%s\s*%s" % (KEY_MARK, KEY_MARK))


def _expand_dice(m: re.Match) -> str:
    count, sides = m.group(1), m.group(2)
    lead = "%s " % NUMBER_WORDS.get(count, count) if count else ""
    return "%sdee %s" % (lead, " ".join(NUMBER_WORDS.get(c, c) for c in sides))


def to_speech(text: str, tokens: dict) -> str:
    """Card text (BBCode + {tokens} + Ork dialect) -> a line Piper can read.

    Acronyms are left ALL-CAPS on purpose: espeak spells "CP" out as "C P",
    which is exactly how a player says it. Barks are sentence-cased upstream in
    _join() instead, so a whole shouted line does not get spelled letter by
    letter while "+1 CP" still does.
    """
    out = TOKEN_RE.sub(lambda m: _speak_token(m.group(1), m.group(2) or "", tokens), text)
    out = KEY_RUN_RE.sub(", ", out)                    # W|A|S|D -> "W, A, S, D"
    out = out.replace(KEY_MARK, " ")
    out = BBCODE_RE.sub("", out)
    out = re.sub(r"\[([^\]]*)\]", r"\1", out)          # keep on-screen bracketed words
    out = INCHES_RE.sub(r"\1 inches", out)
    out = DICE_RE.sub(_expand_dice, out)
    for sym, say in SYMBOL_SPEECH.items():
        out = out.replace(sym, say)

    def _sub_map(mapping, pattern):
        def _repl(m: re.Match) -> str:
            word = m.group(0)
            hit = mapping.get(word.lower())
            return word if hit is None else (hit.upper() if word.isupper() and len(word) > 1 else hit)
        return lambda s: re.sub(pattern, _repl, s)

    out = _sub_map(ORK_APOSTROPHE, r"[A-Za-z]*'[A-Za-z]+|[A-Za-z]+'")(out)
    out = re.sub(r"(^|\s)'(\w)", r"\1\2", out)          # any leftover 'ere -> ere
    out = re.sub(r"(\w)'(\s|$)", r"\1\2", out)          # any leftover movin' -> movin
    out = _sub_map(ORK_PRONUNCIATION, r"[A-Za-z]+")(out)
    out = re.sub(r"\s+([,.;:!?])", r"\1", out)          # "word , word" -> "word, word"
    out = re.sub(r"([,;:])\1+", r"\1", out)
    out = re.sub(r"\(\s*\)", "", out)
    out = re.sub(r"\s+", " ", out).strip()
    return out


# --------------------------------------------------------------------------
# Line extraction
# --------------------------------------------------------------------------

class Line:
    """One clip: the bark plus the body for a single step and input device."""

    def __init__(self, clip_id, lesson_id, step_id, variant, display, speech):
        self.clip_id = clip_id
        self.lesson_id = lesson_id
        self.step_id = step_id
        self.variant = variant
        self.display = display
        self.speech = speech

    def digest(self, settings_sig: str) -> str:
        return hashlib.sha256(("%s\x00%s" % (self.speech, settings_sig)).encode()).hexdigest()[:16]


def _clip_id(lesson_id: str, step_id: str, variant: str) -> str:
    return "%s__%s__%s" % (lesson_id, step_id, variant)


def collect_lines(tokens: dict) -> list:
    """Every clip the tutorial needs, in lesson then step order.

    A step is one clip per device it can be shown on, because the pad and
    keyboard bodies name different controls. Steps whose two bodies normalise
    to the same speech (no device-specific control named) collapse to one
    shared "any" clip rather than synthesising the same audio twice.
    """
    lines = []
    for path in sorted(glob.glob(os.path.join(LESSON_DIR, "*.json"))):
        with open(path) as f:
            lesson = json.load(f)
        lesson_id = str(lesson.get("id", os.path.basename(path).split(".")[0]))
        for step in lesson.get("steps", []):
            step_id = str(step.get("id", ""))
            prompt = step.get("prompt", {})
            bark = str(prompt.get("bark", "")).strip()
            bodies = {}
            for variant, keys in (("kbm", ("kbm", "text", "pad")), ("pad", ("pad", "text", "kbm"))):
                for key in keys:
                    if prompt.get(key):
                        bodies[variant] = str(prompt[key])
                        break
            if not bodies and not bark:
                continue
            speech = {v: to_speech(_join(bark, b), tokens) for v, b in bodies.items()}
            display = {v: _join(bark, b) for v, b in bodies.items()}
            if len(speech) == 2 and speech["kbm"] == speech["pad"]:
                lines.append(Line(_clip_id(lesson_id, step_id, "any"), lesson_id, step_id,
                                  "any", display["kbm"], speech["kbm"]))
                continue
            for variant in sorted(speech):
                lines.append(Line(_clip_id(lesson_id, step_id, variant), lesson_id, step_id,
                                  variant, display[variant], speech[variant]))
        summary = lesson.get("summary", {})
        if summary:
            text = _join(str(summary.get("bark", "")).strip(),
                         " ".join(str(b).rstrip(".") + "." for b in summary.get("bullets", [])))
            if text.strip():
                lines.append(Line(_clip_id(lesson_id, "_summary", "any"), lesson_id, "_summary",
                                  "any", text, to_speech(text, tokens)))
    return lines


def _join(bark: str, body: str) -> str:
    """Bark + body as one spoken line.

    Barks are authored SHOUTED ("OI, LISTEN UP!"). espeak spells a run of
    capitals out letter by letter, so the shout is folded to sentence case here
    — the volume comes from the delivery and the compressor, not the spelling.
    Doing it here rather than in to_speech() keeps in-body acronyms (CP, AP, OC)
    capitalised, which is how they should be read.
    """
    bark = bark.strip()
    body = body.strip()
    if bark and bark.upper() == bark:
        bark = bark.capitalize()
    if not bark:
        return body
    if not body:
        return bark
    if bark[-1] not in ".!?":
        bark += "!"
    return "%s %s" % (bark, body)


# --------------------------------------------------------------------------
# Synthesis + the ork chain
# --------------------------------------------------------------------------

def ork_chain(intensity: float) -> list:
    """SoX effect chain that turns a northern-English narrator into an Ork.

    `intensity` (0..1) scales every colouring stage. Two details are load-bearing
    and were both found the hard way:

    * The leading `gain -10`, the `gain -6` before the reverb and the `-3` make-up
      on the compander are HEADROOM. Without them the EQ boosts, the compander
      and the reverb tail each clip, which sounds like crackle rather than grit.
    * `compand` runs BEFORE `reverb`. In the other order SoX aborts with
      "compand: multi-channel effect flowed asymmetrically" and emits a 0.2s
      stub — while still exiting 0 (see synth() for the guard).
    """
    i = max(0.0, min(1.0, intensity))
    pitch_cents = int(-100 - 300 * i)         # -1 .. -4 semitones
    chest_db = 1.0 + 2.5 * i                  # low-end body
    throat_db = 0.5 + 2.0 * i                 # the honk that reads as "Ork"
    hiss_db = -(1.0 + 3.5 * i)                # take the narrator sheen off
    drive = 4 + 10 * i                        # rasp, gently — this is a tutorial
    room = 8 + 12 * i
    return [
        "gain", "-10",
        "pitch", str(pitch_cents),
        "equalizer", "110", "1.0q", "%.2f" % chest_db,
        "equalizer", "700", "1.2q", "%.2f" % throat_db,
        "equalizer", "3500", "2.0q", "%.2f" % hiss_db,
        "overdrive", "%.1f" % drive, "%.1f" % (20 + 10 * i),
        # Even out the shout-to-mutter range so no line needs a volume nudge.
        "compand", "0.02,0.20", "-50,-45,-20,-14,0,-8", "-3", "-90", "0.1",
        "gain", "-6",
        "reverb", "%d" % room, "50", "40", "100", "10", "-3",
        "gain", "-n", "-1.5",
    ]


def _duration(path: str) -> float:
    probe = subprocess.run(["soxi", "-D", path], capture_output=True, text=True)
    return float(probe.stdout.strip() or 0.0)


def synth(text: str, out_ogg: str, voice: str, intensity: float, quality: int) -> float:
    """Piper -> ork chain -> Ogg Vorbis. Returns clip length in seconds."""
    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, "raw.wav")
        orked = os.path.join(tmp, "ork.wav")
        subprocess.run(
            [sys.executable, "-m", "piper", "-m", voice, "-f", raw,
             "--length-scale", str(PIPER_LENGTH_SCALE),
             "--noise-scale", str(PIPER_NOISE_SCALE),
             "--noise-w-scale", str(PIPER_NOISE_W),
             "--sentence-silence", str(SENTENCE_SILENCE)],
            input=text.encode(), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        raw_seconds = _duration(raw)
        if raw_seconds <= 0.0:
            raise RuntimeError("piper produced no audio for: %s" % text[:80])

        sox = subprocess.run(["sox", raw, orked] + ork_chain(intensity), capture_output=True)
        stderr = sox.stderr.decode()
        # SoX exits 0 on a mid-chain abort ("FAIL <effect>: ...") and leaves a
        # truncated stub behind, so neither the return code nor the file's
        # existence proves anything. Check the text AND the length.
        if sox.returncode != 0 or "FAIL" in stderr:
            raise RuntimeError("sox failed: %s" % (stderr.strip()[:400] or "rc=%d" % sox.returncode))
        out_seconds = _duration(orked)
        if abs(out_seconds - raw_seconds) > 0.5:
            raise RuntimeError("sox truncated %.2fs to %.2fs (chain aborted?)"
                               % (raw_seconds, out_seconds))
        if "clipped" in stderr:
            print("  WARN clipping in %s: %s"
                  % (os.path.basename(out_ogg), stderr.strip()[:200]))

        os.makedirs(os.path.dirname(out_ogg), exist_ok=True)
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", orked,
             "-c:a", "libvorbis", "-q:a", str(quality), "-ac", "1", out_ogg],
            check=True, capture_output=True)
        return out_seconds


# --------------------------------------------------------------------------

def load_tokens() -> dict:
    if not os.path.exists(TOKENS_PATH):
        sys.exit("missing %s — run:\n  godot --headless --path 40k "
                 "--script res://tools/dump_vo_tokens.gd" % TOKENS_PATH)
    with open(TOKENS_PATH) as f:
        return json.load(f)


def require_tools(voice: str) -> None:
    missing = [t for t in ("sox", "soxi", "ffmpeg") if shutil.which(t) is None]
    if missing:
        sys.exit("missing host tools: %s (apt-get install -y sox ffmpeg)" % ", ".join(missing))
    if subprocess.run([sys.executable, "-c", "import piper"], capture_output=True).returncode != 0:
        sys.exit("piper-tts not installed (pip3 install piper-tts)")
    if not os.path.exists(voice):
        sys.exit("voice model not found: %s\n  python3 -m piper.download_voices "
                 "--download-dir %s en_GB-northern_english_male-medium"
                 % (voice, os.path.dirname(voice) or "."))


def self_test() -> int:
    """Pin the text normalisation. Every case here is a bug that shipped once."""
    tokens = load_tokens()
    cases = [
        # (card text, must appear, must NOT appear)
        ("Press {key:hotkey_help} for help.", ["Shift forward slash"], ["{", "/"]),
        ("Press {key:select_all} to grab da lot.", ["Control A"], ["Ctrl", "+"]),
        # W / Up: only the primary binding is spoken, and a RUN of key tokens is
        # comma-joined or it reads as one garbled word.
        ("Pan wiv {key:camera_pan_up} {key:camera_pan_left} {key:camera_pan_down}.",
         ["W, A, S"], ["Up", "Left", "Down"]),
        ("Shove {rs} an' squeeze {rt}.", ["the right stick", "the right trigger"], ["{"]),
        ("Press {a} then {menu}.", ["the A button", "the Menu button"], ["✚", "☰"]),
        ("Tap {dpad} up.", ["the D pad"], ["✚"]),
        # BBCode is formatting and goes; a bracketed on-screen word is content
        # and stays, minus its brackets.
        ("[b]Bold[/b] and [i]italic[/i] and [Escape] the key.",
         ["Bold", "italic", "Escape"], ["[b]", "[/b]", "[i]", "[Escape]"]),
        # Measurements and dice have to become words.
        ('Move within 3" an\' roll 2D6.', ["3 inches", "two dee six"], ['"', "2D6"]),
        ("Roll a D6.", ["dee six"], ["D6"]),
        # "+1 CP" — the plus is spoken, the acronym stays capitalised so espeak
        # spells it "C P" rather than reading it as a word.
        ("You get +1 CP.", ["plus 1 CP"], ["+1"]),
        # Dropped H and the an'/an collision: "an'" becomes "and", the ARTICLE
        # "an" must not. An ORDINARY contraction ("here's") keeps its apostrophe —
        # espeak reads those correctly and stripping it makes "heres".
        ("'Ere's an 'ard git an' 'is mates.",
         ["here's", "an hard", "and his"], [" 'ard", "an' ", " 'is"]),
        # A shouted bark is folded to sentence case by _join, not by to_speech —
        # so an in-body acronym next to it survives.
        (None, None, None),
    ]
    failures = []
    for text, wants, nots in cases:
        if text is None:
            continue
        got = to_speech(text, tokens)
        for w in wants:
            if w not in got:
                failures.append("%-46r missing %r -> %r" % (text, w, got))
        for n in nots:
            if n in got:
                failures.append("%-46r leaked  %r -> %r" % (text, n, got))

    joined = _join("OI, LISTEN UP!", "You get +1 CP.")
    if not joined.startswith("Oi, listen up!"):
        failures.append("bark not sentence-cased: %r" % joined)
    if "CP" not in to_speech(joined, tokens):
        failures.append("acronym lost to bark casing: %r" % to_speech(joined, tokens))

    # Every clip id must be unique, or one step silently overwrites another's file.
    lines = collect_lines(tokens)
    ids = [l.clip_id for l in lines]
    if len(ids) != len(set(ids)):
        dupes = sorted({i for i in ids if ids.count(i) > 1})
        failures.append("duplicate clip ids: %s" % dupes)
    # Nothing may reach the phonemizer with markup still in it.
    for l in lines:
        for bad in ("{", "}", "[b]", "[/b]", KEY_MARK):
            if bad in l.speech:
                failures.append("%s still contains %r: %r" % (l.clip_id, bad, l.speech[:90]))

    for f in failures:
        print("FAIL %s" % f)
    print("\nself-test: %d lesson lines, %d failures" % (len(lines), len(failures)))
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--voice", default=DEFAULT_VOICE, help="path to the Piper .onnx model")
    ap.add_argument("--ork-intensity", type=float, default=0.75,
                    help="0 = plain narrator, 1 = maximum gravel (default 0.75)")
    ap.add_argument("--quality", type=int, default=1,
                    help="libvorbis -q:a (default 1, ~48kbps mono)")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    ap.add_argument("--force", action="store_true", help="regenerate even unchanged clips")
    ap.add_argument("--only", default="", help="substring filter on clip id")
    ap.add_argument("--dry-run", action="store_true", help="print the speakable text and stop")
    ap.add_argument("--say", default="", help="audition one line to /tmp and exit")
    ap.add_argument("--self-test", action="store_true",
                    help="check the text normalisation and clip ids, then exit")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    if args.say:
        require_tools(args.voice)
        out = "/tmp/ork_say.ogg"
        speech = to_speech(args.say, load_tokens())
        print("speech: %s" % speech)
        print("%.2fs -> %s" % (synth(speech, out, args.voice, args.ork_intensity, args.quality), out))
        return 0

    tokens = load_tokens()
    lines = [l for l in collect_lines(tokens) if args.only in l.clip_id]
    settings_sig = "|".join(str(x) for x in [
        PIPELINE_VERSION, os.path.basename(args.voice), args.ork_intensity, args.quality,
        PIPER_LENGTH_SCALE, PIPER_NOISE_SCALE, PIPER_NOISE_W, SENTENCE_SILENCE])

    if args.dry_run:
        for l in lines:
            print("--- %s\n%s" % (l.clip_id, l.speech))
        print("\n%d clips, %d chars" % (len(lines), sum(len(l.speech) for l in lines)))
        return 0

    require_tools(args.voice)
    old = {}
    if os.path.exists(MANIFEST_PATH):
        with open(MANIFEST_PATH) as f:
            old = json.load(f).get("clips", {})

    todo = []
    clips = {}
    for l in lines:
        digest = l.digest(settings_sig)
        rel = "assets/audio/vo/tutorial/%s.ogg" % l.clip_id
        prev = old.get(l.clip_id)
        if (not args.force and prev and prev.get("sha") == digest
                and os.path.exists(os.path.join(PROJECT, rel))):
            clips[l.clip_id] = prev
            continue
        todo.append((l, digest, rel))

    print("%d clips total, %d to (re)generate, %d cached"
          % (len(lines), len(todo), len(lines) - len(todo)))

    failures = []

    def work(item):
        line, digest, rel = item
        seconds = synth(line.speech, os.path.join(PROJECT, rel), args.voice,
                        args.ork_intensity, args.quality)
        return line, digest, rel, seconds

    if todo:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            for n, fut in enumerate(concurrent.futures.as_completed(
                    [pool.submit(work, it) for it in todo]), 1):
                try:
                    line, digest, rel, seconds = fut.result()
                except Exception as exc:                      # noqa: BLE001 — report, keep going
                    failures.append(str(exc))
                    print("  FAIL %s" % str(exc)[:300])
                    continue
                clips[line.clip_id] = {
                    "path": "res://" + rel,
                    "lesson": line.lesson_id,
                    "step": line.step_id,
                    "variant": line.variant,
                    "sha": digest,
                    "seconds": round(seconds, 2),
                    "text": line.speech,
                }
                print("  [%d/%d] %-52s %5.2fs" % (n, len(todo), line.clip_id, seconds))

    total = sum(c.get("seconds", 0.0) for c in clips.values())
    manifest = {
        "_comment": "Generated by tools/generate_tutorial_vo.py — do not hand-edit.",
        "voice": os.path.basename(args.voice),
        "ork_intensity": args.ork_intensity,
        "pipeline_version": PIPELINE_VERSION,
        "clips": dict(sorted(clips.items())),
    }
    with open(MANIFEST_PATH, "w") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")

    size = sum(os.path.getsize(os.path.join(PROJECT, c["path"][len("res://"):]))
               for c in clips.values()
               if os.path.exists(os.path.join(PROJECT, c["path"][len("res://"):])))
    print("\nwrote %s\n%d clips, %.1f min of audio, %.1f MB on disk"
          % (MANIFEST_PATH, len(clips), total / 60.0, size / 1e6))
    if failures:
        print("%d FAILURES" % len(failures))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
