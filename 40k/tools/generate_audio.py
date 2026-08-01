#!/usr/bin/env python3
"""Procedurally generate the game's music and UI sound effects.

Pure standard-library (math + wave) — no numpy, no external samples, so every
byte is original and unambiguously ours to ship (no third-party licence, no
attribution requirement). Run from the repo:

    python3 40k/tools/generate_audio.py

Writes .wav files into 40k/assets/audio/. Godot imports them; MusicManager.gd
plays the two ambient beds (menu + battle) on loop and the UI cues on demand.

Design: dark, slow, grimdark-tabletop ambience — layered detuned drones on a
minor tonality with slow amplitude swells and a filtered wind bed. The battle
bed adds a low heartbeat pulse and a tension interval. Kept intentionally
sparse so it sits under the UI without fatiguing on repeat.
"""
import math
import os
import struct
import wave

SR = 22050  # mono 16-bit; ample for ambient pads, half the size of 44.1k
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")


def _write(path, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = max(-1.0, min(1.0, s))
            frames += struct.pack("<h", int(v * 32767))
        w.writeframes(bytes(frames))
    print("wrote %s (%d samples, %.1fs)" % (path, len(samples), len(samples) / SR))


def _lowpass(samples, alpha):
    """One-pole low-pass for warmth. alpha in (0,1]; smaller = darker."""
    out = [0.0] * len(samples)
    prev = 0.0
    for i, s in enumerate(samples):
        prev = prev + alpha * (s - prev)
        out[i] = prev
    return out


def _crossfade_loop(samples, fade):
    """Make a buffer loop seamlessly by crossfading its tail over its head."""
    n = len(samples)
    fade = min(fade, n // 2)
    out = list(samples)
    for i in range(fade):
        a = out[i]
        b = out[n - fade + i]
        t = i / fade
        # tail fades out as head fades in; write the blended head, drop the tail
        out[i] = a * t + b * (1.0 - t)
    return out[: n - fade]


def _drone(dur, freqs, detune=0.6, amp=0.12):
    """Sum of slightly detuned sine partials — a warm pad."""
    n = int(dur * SR)
    out = [0.0] * n
    for base in freqs:
        for d in (-detune, 0.0, detune):
            f = base + d
            ph = 0.0
            step = 2 * math.pi * f / SR
            for i in range(n):
                out[i] += math.sin(ph) * amp
                ph += step
    return out


def _swell(samples, period, depth=0.5, base=0.5):
    """Slow amplitude LFO (breathing). period in seconds."""
    n = len(samples)
    out = [0.0] * n
    for i in range(n):
        lfo = base + depth * 0.5 * (1 - math.cos(2 * math.pi * i / (period * SR)))
        out[i] = samples[i] * lfo
    return out


def _wind(dur, amp=0.05, seed=1):
    """Filtered pseudo-noise bed (deterministic LCG so runs are reproducible)."""
    n = int(dur * SR)
    out = [0.0] * n
    x = seed
    for i in range(n):
        x = (1103515245 * x + 12345) & 0x7FFFFFFF
        out[i] = ((x / 0x7FFFFFFF) * 2 - 1) * amp
    out = _lowpass(out, 0.02)   # deep rumble
    out = _lowpass(out, 0.02)
    return out


def _heartbeat(dur, bpm=48, amp=0.22):
    """Low pulsing thump for the battle bed."""
    n = int(dur * SR)
    out = [0.0] * n
    interval = 60.0 / bpm
    beat_samples = int(interval * SR)
    for start in range(0, n, beat_samples):
        # short 60Hz sine burst with fast decay
        for i in range(min(int(0.35 * SR), n - start)):
            env = math.exp(-i / (0.10 * SR))
            out[start + i] += math.sin(2 * math.pi * 58 * i / SR) * env * amp
    return out


def mix(*layers):
    n = max(len(l) for l in layers)
    out = [0.0] * n
    for l in layers:
        for i in range(len(l)):
            out[i] += l[i]
    return out


def make_menu_theme():
    dur = 44.0
    # A minor-ish drone: A2, E3, C4 (root, fifth, minor third up an octave)
    a2, e3, c4, a3 = 110.0, 164.81, 261.63, 220.0
    root = _swell(_drone(dur, [a2, e3], detune=0.5, amp=0.13), period=11.0, depth=0.6, base=0.4)
    shimmer = _swell(_drone(dur, [c4, a3], detune=0.8, amp=0.06), period=17.0, depth=0.8, base=0.25)
    bed = _wind(dur, amp=0.06, seed=7)
    out = mix(root, shimmer, bed)
    out = _lowpass(out, 0.35)
    out = _crossfade_loop(out, int(2.0 * SR))
    peak = max(abs(s) for s in out) or 1.0
    out = [s / peak * 0.72 for s in out]
    _write(os.path.join(OUT, "menu_theme.wav"), out)


def make_battle_theme():
    dur = 40.0
    # Same tonic, darker + a tension major-second (A2 + B2) and a heartbeat.
    a2, e3, b2, d4 = 110.0, 164.81, 123.47, 293.66
    root = _swell(_drone(dur, [a2, e3], detune=0.5, amp=0.12), period=9.0, depth=0.5, base=0.5)
    tension = _swell(_drone(dur, [b2, d4], detune=0.7, amp=0.045), period=13.0, depth=0.9, base=0.15)
    beat = _heartbeat(dur, bpm=50, amp=0.20)
    bed = _wind(dur, amp=0.07, seed=13)
    out = mix(root, tension, beat, bed)
    out = _lowpass(out, 0.4)
    out = _crossfade_loop(out, int(2.0 * SR))
    peak = max(abs(s) for s in out) or 1.0
    out = [s / peak * 0.78 for s in out]
    _write(os.path.join(OUT, "battle_theme.wav"), out)


def _blip(freq_start, freq_end, dur, amp=0.5, kind="sine"):
    n = int(dur * SR)
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        t = i / n
        f = freq_start + (freq_end - freq_start) * t
        ph += 2 * math.pi * f / SR
        env = math.sin(math.pi * t)  # smooth attack/decay
        if kind == "sine":
            s = math.sin(ph)
        else:  # soft triangle
            s = 2 / math.pi * math.asin(math.sin(ph))
        out[i] = s * env * amp
    return out


def make_ui_sfx():
    # Short, soft, low-mid cues that suit the parchment/gold theme.
    _write(os.path.join(OUT, "ui_hover.wav"), _blip(880, 1040, 0.05, amp=0.28))
    _write(os.path.join(OUT, "ui_click.wav"), _blip(520, 680, 0.07, amp=0.42))
    _write(os.path.join(OUT, "ui_confirm.wav"),
           mix(_blip(392, 523, 0.10, amp=0.4), _blip(523, 784, 0.14, amp=0.3)))
    _write(os.path.join(OUT, "ui_back.wav"), _blip(440, 300, 0.09, amp=0.36))


if __name__ == "__main__":
    make_menu_theme()
    make_battle_theme()
    make_ui_sfx()
    print("done.")
