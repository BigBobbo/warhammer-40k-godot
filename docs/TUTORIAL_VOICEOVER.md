# Tutorial voiceover (da Ork narrator)

Every tutorial card is read aloud by an Ork. The clips are **pre-rendered
assets**, not runtime text-to-speech: an offline generator turns the lesson
files into Ogg Vorbis, and the game only picks a file and plays it. So the
shipped build has no TTS dependency, no model download, no network call, and no
delay between a card appearing and the voice starting.

| Piece | Path |
| --- | --- |
| Generator | `40k/tools/generate_tutorial_vo.py` |
| Token dump (keys/glyphs) | `40k/tools/dump_vo_tokens.gd` → `40k/data/tutorials/vo_tokens.json` |
| Clips | `40k/assets/audio/vo/tutorial/*.ogg` (122 clips, ~27 min, ~6.7 MB) |
| Manifest | `40k/data/tutorials/vo_manifest.json` |
| Runtime | `40k/autoloads/TutorialVoice.gd` (autoload, "Voice" bus) |
| Player controls | Settings › Audio → *Voice Volume*, *Tutorial Voiceover*; card → **🔊 Again** |
| Windowed test | `40k/tests/scenarios/sp/tut_voiceover.json` |

## Player-facing behaviour

* The narrator starts when a card appears and stops when the tutorial exits.
* **🔊 Again** on the card replays the current line. It is the only on-screen
  sign the card is narrated, and it is hidden entirely in a build with no clips.
* Steps have **per-device clips**. The keyboard card says "press I", the pad card
  says "press the Y button" — swapping device mid-lesson re-renders the card and
  the spoken line follows it. Steps that read identically on both devices share a
  single `any` clip instead of being synthesised twice.
* Settings › Audio → **Tutorial Voiceover** cuts the line already playing (not
  just the next one); turning it back on speaks the card on screen immediately.
* **Voice Volume** is its own bus, so the narrator can be turned down without
  silencing the UI cues, and vice versa.

## Regenerating the clips

Only needed when lesson text, a default keybinding, or the voice settings change.

```bash
# one-time host setup (Debian/Ubuntu)
apt-get install -y sox ffmpeg
pip3 install piper-tts
python3 -m piper.download_voices --download-dir ~/piper-voices \
    en_GB-northern_english_male-medium

# if a DEFAULT KEYBINDING or a glyph label changed, refresh the token map first
godot --headless --path 40k --script res://tools/dump_vo_tokens.gd

# regenerate (incremental — unchanged steps are skipped)
python3 40k/tools/generate_tutorial_vo.py

# useful flags
python3 40k/tools/generate_tutorial_vo.py --self-test       # normalisation checks
python3 40k/tools/generate_tutorial_vo.py --dry-run         # print spoken text only
python3 40k/tools/generate_tutorial_vo.py --say "OI! Move da boyz!"
python3 40k/tools/generate_tutorial_vo.py --ork-intensity 1.0 --force
```

The manifest stores a hash of each clip's *speakable text plus the voice
settings*, so editing one lesson line regenerates one clip. Changing
`--ork-intensity`, the voice, or `PIPELINE_VERSION` regenerates everything.

## How the Ork voice is made

`en_GB-northern_english_male` is the base: Orks are written with broad
working-class northern-English accents, so the model already starts in the right
place and the DSP only has to add size and gravel.

The SoX chain (`ork_chain()`) is pitch down ~3.5 semitones → chest EQ at 110 Hz →
throat honk at 700 Hz → de-sheen at 3.5 kHz → light overdrive → compander →
small room. `--ork-intensity` (0–1, default 0.75) scales every colouring stage.

It is deliberately restrained. **This is a tutorial: intelligibility beats
character.** Verified by synthesising the same line with and without the chain
and transcribing both — the processed clip transcribes as well as the raw synth.

Two things in that chain are load-bearing and were found the hard way:

* **`compand` runs before `reverb`.** In the other order SoX aborts with
  `compand: multi-channel effect flowed asymmetrically`, writes a 0.2-second
  stub — **and still exits 0**. `synth()` therefore checks stderr for `FAIL` and
  compares input/output duration; the return code alone proves nothing.
* **The gain trims are headroom**, not level tweaks. Without them the EQ boosts,
  the compander and the reverb tail each clip, which sounds like crackle rather
  than grit.

## Speakable text

Card text is BBCode plus `{token}` chips plus Ork dialect, none of which a
phonemizer handles raw. `to_speech()` expands tokens using the game's *real*
bindings (`vo_tokens.json`, dumped from `KeybindingManager`/`GlyphDB`), strips
BBCode while keeping bracketed on-screen words, turns `3"` into "3 inches" and
`2D6` into "two dee six", and respells the handful of dialect words the
phonemizer gets wrong. Barks are folded from `SHOUTING` to sentence case, but
in-body acronyms stay capitalised so `+1 CP` is read "plus one C P".

`ORK_PRONUNCIATION` is a *pronunciation* map, not a translation — the Ork keeps
his accent, he just stops mispronouncing himself. Only add an entry when the
default reading is genuinely wrong; check with `--say` before and after.

### Known limitation

Clips speak the **default** keybinding. A player who rebinds a key sees the new
key on the card but hears the old one. Pad glyphs are unaffected (they are spoken
as button names). Re-run `dump_vo_tokens.gd` + the generator if a *default* ever
changes.
