#!/usr/bin/env python3
"""Synthesises the app's sound palette.

Every cue is made here from sine partials, filtered air and a soft
convolution reverb, so the sounds are original and need no licence. They
share one key (D major pentatonic, with a Lydian G-sharp and C-sharp for
the brighter moments) and one "glass" voice, so the whole app sounds like
one instrument.

    python3 tools/sounds/generate_sounds.py

writes the in-app cues as AAC .m4a and the notification chime as 16-bit
PCM .caf (the formats iOS requires for it) to "Stop Swiping/Resources/Sounds".
Only numpy and macOS's afconvert are needed.
"""

import math
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44_100
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "Stop Swiping", "Resources", "Sounds")


def midi(note: float) -> float:
    return 440.0 * 2 ** ((note - 69) / 12)


# D major pentatonic (+ Lydian colour), as MIDI numbers.
D4, A4 = 62, 69
D5, E5, Fs5, Gs5, A5, B5 = 74, 76, 78, 80, 81, 83
Cs6, D6, E6, Fs6, A6, B6 = 85, 86, 88, 90, 93, 95
D7, E7, Fs7, A7 = 98, 100, 102, 105
SPARKLE_NOTES = [D6, E6, Fs6, A6, B6, D7, E7, Fs7, A7]


def silence(seconds: float) -> np.ndarray:
    return np.zeros((int(seconds * SR), 2))


def place(mix: np.ndarray, sound: np.ndarray, at: float, gain: float = 1.0, pan: float = 0.0) -> None:
    """Adds a mono or stereo sound at `at` seconds, panned -1 (left) … 1 (right)."""
    start = int(at * SR)
    if sound.ndim == 1:
        left = math.cos((pan + 1) * math.pi / 4)
        right = math.sin((pan + 1) * math.pi / 4)
        sound = np.stack([sound * left, sound * right], axis=1) * math.sqrt(2)
    end = min(len(mix), start + len(sound))
    if end > start:
        part = sound[: end - start] * gain
        if end - start < len(sound):
            # The mix ends before the sound does: fade it out at the cut
            # instead of leaving a click there.
            r = min(len(part), int(0.04 * SR))
            part[-r:] *= (0.5 + 0.5 * np.cos(np.linspace(0, math.pi, r)))[:, None]
        mix[start:end] += part


def soft_attack(n: int, attack: float) -> np.ndarray:
    env = np.ones(n)
    a = max(1, int(attack * SR))
    a = min(a, n)
    env[:a] = 0.5 - 0.5 * np.cos(np.linspace(0, math.pi, a))
    return env


def soft_release(n: int, release: float = 0.06) -> np.ndarray:
    """A short fade at the very end, so a note cut off at `duration` ends at
    silence. Without it the cut is a step in the waveform: a click that the
    reverb then smears into a small knock after every note."""
    env = np.ones(n)
    r = min(n, max(1, int(release * SR)))
    env[-r:] = 0.5 + 0.5 * np.cos(np.linspace(0, math.pi, r))
    return env


def glass(note: float, duration: float = 1.2, decay: float = 0.6, brightness: float = 1.0,
          attack: float = 0.004, shimmer: float = 0.0016) -> np.ndarray:
    """A glass/celesta bell: slightly inharmonic partials, each with a quieter
    detuned twin so it shimmers, the upper ones dying away first.

    The twin is kept well below its partner: two equal voices cancel at every
    beat, which turned short notes into a tremolo (a D6 dipped ~15 dB about
    four times a second) and left a second swell at the end of each note."""
    f = midi(note)
    n = int(duration * SR)
    t = np.arange(n) / SR
    partials = [(1.0, 1.0, 1.0), (2.0, 0.32, 0.55), (2.76, 0.16 * brightness, 0.38),
                (4.07, 0.09 * brightness, 0.24), (5.43, 0.045 * brightness, 0.15),
                (6.8, 0.02 * brightness, 0.1)]
    out = np.zeros(n)
    for ratio, amp, life in partials:
        freq = f * ratio
        if freq > 16_000:
            continue
        env = np.exp(-t / (decay * life))
        pair = np.sin(2 * math.pi * freq * (1 - shimmer) * t) + 0.3 * np.sin(2 * math.pi * freq * (1 + shimmer) * t + 0.7)
        out += amp * env * pair / 1.3
    return out * soft_attack(n, attack) * soft_release(n)


def soft_tone(note: float, duration: float, decay: float = 0.3, attack: float = 0.012,
              glide: float = 0.0) -> np.ndarray:
    """A round, nearly pure tone with an optional pitch glide (semitones)."""
    n = int(duration * SR)
    t = np.arange(n) / SR
    semis = note + glide * (1 - np.exp(-t / max(duration * 0.25, 1e-3)))
    freq = 440.0 * 2 ** ((semis - 69) / 12)
    phase = 2 * math.pi * np.cumsum(freq) / SR
    out = np.sin(phase) + 0.12 * np.sin(2 * phase)
    return out * np.exp(-t / decay) * soft_attack(n, attack) * soft_release(n, 0.03)


def pad(notes, duration: float, attack: float = 1.0, release: float = 1.0, level: float = 1.0) -> np.ndarray:
    """A slow, breathing chord of detuned sines with a light vibrato."""
    n = int(duration * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    rng = np.random.default_rng(int(sum(notes)))
    for note in notes:
        f = midi(note)
        for detune in (-0.004, 0.0, 0.0045):
            vib = 1 + 0.0018 * np.sin(2 * math.pi * (4.6 + rng.random()) * t + rng.random() * 6)
            phase = 2 * math.pi * np.cumsum(f * (1 + detune) * vib) / SR
            out += np.sin(phase) / 3
    env = np.minimum(1, t / max(attack, 1e-3)) ** 2
    tail = np.clip((duration - t) / max(release, 1e-3), 0, 1) ** 1.5
    return out * env * tail * level / max(len(notes), 1)


def air(duration: float, f_from: float, f_to: float, q: float = 1.2, seed: int = 1,
        shape=None) -> np.ndarray:
    """Breathy noise through a band-pass whose centre glides from f_from to
    f_to (a state-variable filter, run per sample)."""
    n = int(duration * SR)
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(n)
    t = np.linspace(0, 1, n)
    centre = f_from * (f_to / f_from) ** t
    g = np.tan(np.pi * np.minimum(centre, SR * 0.45) / SR)
    k = 1.0 / q
    out = np.empty(n)
    ic1 = ic2 = 0.0
    for i in range(n):
        gi = g[i]
        a1 = 1.0 / (1.0 + gi * (gi + k))
        v3 = noise[i] - ic2
        v1 = a1 * ic1 + gi * a1 * v3
        v2 = ic2 + gi * v1
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        out[i] = v1
    if shape is None:
        shape = np.sin(np.pi * t) ** 2
    else:
        shape = shape(t)
    return out * shape * 0.35


def sparkles(duration: float, count: int, seed: int, notes=SPARKLE_NOTES, density=None,
             level: float = 1.0) -> np.ndarray:
    """Tiny high bells sprinkled over time, scattered across the stereo field."""
    mix = silence(duration + 1.0)
    rng = np.random.default_rng(seed)
    times = rng.random(count)
    if density is not None:
        times = density(times)
    for at in np.sort(times) * duration:
        note = notes[rng.integers(len(notes))]
        grain = glass(note, duration=0.7, decay=rng.uniform(0.12, 0.3), brightness=0.6,
                      attack=0.002)
        place(mix, grain, at, gain=level * rng.uniform(0.25, 0.7), pan=rng.uniform(-0.8, 0.8))
    return mix


def reverb(dry: np.ndarray, seconds: float = 2.4, mix: float = 0.35, predelay: float = 0.018,
           seed: int = 7) -> np.ndarray:
    """Convolution with a decaying stereo noise tail that darkens as it fades."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    wet = np.zeros((len(dry) + n + int(predelay * SR), 2))
    kernel = np.ones(12) / 12
    for ch in range(2):
        noise = rng.standard_normal(n)
        dark = np.convolve(noise, kernel, mode="same")
        dark = np.convolve(dark, kernel, mode="same") * 3
        blend = np.clip(t / seconds * 1.6, 0, 1)
        ir = (noise * (1 - blend) + dark * blend) * np.exp(-6.9 * t / seconds)
        ir[: int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))
        ir /= np.sqrt(np.sum(ir ** 2))
        size = 1 << int(np.ceil(np.log2(len(dry) + n)))
        conv = np.fft.irfft(np.fft.rfft(dry[:, ch], size) * np.fft.rfft(ir, size), size)[: len(dry) + n]
        start = int(predelay * SR)
        wet[start:start + len(conv), ch] = conv
    out = np.zeros_like(wet)
    out[: len(dry)] += dry * (1 - mix * 0.5)
    out += wet * mix
    return out


def finish(sound: np.ndarray, peak_db: float) -> np.ndarray:
    """Trims the silent tail, fades out, and normalises the peak."""
    level = np.max(np.abs(sound), axis=1)
    threshold = np.max(level) * 10 ** (-50 / 20)
    last = np.nonzero(level > threshold)[0]
    end = int(last[-1]) + 1 if len(last) else len(sound)
    sound = sound[:end].copy()
    fade = min(len(sound), int(0.08 * SR))
    sound[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
    # Remove any DC offset the filters left, then normalise.
    sound -= sound.mean(axis=0)
    return sound / np.max(np.abs(sound)) * 10 ** (peak_db / 20)


# --------------------------------------------------------------------------
# The cues
# --------------------------------------------------------------------------

def entrance() -> np.ndarray:
    """The welcome light threads in: air rising, stars gathering, one chord."""
    mix = silence(5.2)
    place(mix, air(3.0, 260, 3400, q=1.6, seed=3, shape=lambda t: np.sin(np.pi * np.minimum(t * 0.62, 1) ** 1.3) ** 2), 0.0, 0.55)
    place(mix, pad([D4, A4, E5], 3.4, attack=1.6, release=1.4, level=0.45), 0.1)
    place(mix, sparkles(1.6, 14, seed=11, density=lambda x: x ** 0.6, level=0.5), 1.25)
    for note, at, pan in ((D6, 2.72, -0.3), (A6, 2.78, 0.3), (Fs6, 2.86, 0.0)):
        place(mix, glass(note, 2.2, decay=0.9), at, 0.35, pan)
    return finish(reverb(mix, 2.8, 0.42), -5.0)


def step(note: int) -> np.ndarray:
    """One questionnaire step: a single soft glass note, a step up the scale."""
    mix = silence(1.2)
    place(mix, glass(note, 1.1, decay=0.32, brightness=0.7, attack=0.006, shimmer=0.0), 0.0, 1.0)
    place(mix, glass(note + 12, 0.6, decay=0.12, brightness=0.4, shimmer=0.0), 0.004, 0.12)
    return finish(reverb(mix, 1.4, 0.3), -9.0)


def select() -> np.ndarray:
    """Choosing an answer: the faintest tick of glass."""
    mix = silence(0.4)
    place(mix, glass(A6, 0.4, decay=0.07, brightness=0.5, attack=0.002, shimmer=0.0), 0.0, 1.0)
    return finish(reverb(mix, 0.8, 0.2), -14.0)


def rejection() -> np.ndarray:
    """An answer that can't continue: two muted notes leaning downward."""
    mix = silence(0.9)
    place(mix, soft_tone(A5, 0.5, decay=0.12, attack=0.01), 0.0, 0.8, -0.1)
    place(mix, soft_tone(Fs5, 0.6, decay=0.16, attack=0.01), 0.11, 0.7, 0.1)
    return finish(reverb(mix, 1.0, 0.22), -11.0)


def seal() -> np.ndarray:
    """The finished questionnaire seals: a quick upward twinkle."""
    mix = silence(1.6)
    for i, note in enumerate((D6, Fs6, A6, D7)):
        place(mix, glass(note, 1.2, decay=0.4 - i * 0.05, brightness=0.8), i * 0.055, 0.55 - i * 0.06,
              -0.45 + i * 0.3)
    return finish(reverb(mix, 1.8, 0.35), -7.0)


def strand(duration: float, f_from: float, f_to: float, pan_from: float, pan_to: float, seed: int,
           shape) -> np.ndarray:
    """One backbone of the helix as a ribbon of air travelling across the
    stereo field (equal-power pan, changing over time)."""
    sound = air(duration, f_from, f_to, q=2.4, seed=seed, shape=shape)
    t = np.linspace(0, 1, len(sound))
    pan = pan_from + (pan_to - pan_from) * (t * t * (3 - 2 * t))
    left = np.cos((pan + 1) * math.pi / 4)
    right = np.sin((pan + 1) * math.pi / 4)
    return np.stack([sound * left, sound * right], axis=1) * math.sqrt(2)


# WelcomeLightHelix.Arrival: strands pulled in for 1.9 s after 0.05 s, the
# base pairs laid from 1.5 s for 0.8 s.
ARRIVAL_FLIGHT, RUNGS_START, RUNGS_DURATION = 1.9, 1.5, 0.8


def arrival(mix: np.ndarray, at: float, level: float = 1.0) -> None:
    """The helix flies in: two strands of air drawn in from either side,
    meeting in the middle, then the base pairs clicking into place one by one
    as small glass notes climbing the scale."""
    rise = lambda t: np.sin(np.pi * np.minimum(t * 0.62, 1)) ** 1.6
    start = at + 0.05
    place(mix, strand(ARRIVAL_FLIGHT + 0.2, 500, 1900, -0.95, -0.12, 111, rise), start, 0.55 * level)
    place(mix, strand(ARRIVAL_FLIGHT + 0.2, 560, 2100, 0.95, 0.12, 112, rise), start + 0.04, 0.55 * level)
    place(mix, pad([D4, A4], 2.6, attack=1.4, release=1.2, level=0.3 * level), start + 0.6)
    rungs = (D6, E6, Fs6, A6, B6, D7, E7)
    for i, note in enumerate(rungs):
        when = start + RUNGS_START + RUNGS_DURATION * i / len(rungs)
        place(mix, glass(note, 0.8, decay=0.16, brightness=0.6, attack=0.003), when,
              (0.2 - i * 0.012) * level, 0.35 if i % 2 else -0.35)


def helix_arrival() -> np.ndarray:
    """The helix arriving on the home screen, after launch or a match."""
    mix = silence(4.0)
    arrival(mix, 0.0)
    return finish(reverb(mix, 2.4, 0.4), -7.0)


def complete() -> np.ndarray:
    """The profile is done: the helix flies in for the first time (0.3 s
    after the questionnaire fades), and as it settles an arpeggio climbs
    into a warm, open chord."""
    mix = silence(5.6)
    arrival(mix, 0.3)
    settle = 0.3 + 0.05 + ARRIVAL_FLIGHT
    place(mix, pad([D4, A4, Fs5], 3.0, attack=0.4, release=1.6, level=0.45), settle - 0.2)
    for i, note in enumerate((D5, Fs5, A5, Cs6, E6, A6)):
        place(mix, glass(note, 2.2, decay=0.8, brightness=0.85), settle + i * 0.09, 0.4, -0.5 + i * 0.2)
    place(mix, sparkles(1.4, 10, seed=21, density=lambda x: x ** 1.4, level=0.4), settle + 0.6)
    return finish(reverb(mix, 2.8, 0.42), -5.0)


def departure(mix: np.ndarray, seed: int) -> None:
    """The first 1.6 s of every new match (WelcomeLightMatch.exitDuration):
    the helix's strands are pulled apart, out to either side, leaving room
    for the heart. The mirror image of the arrival."""
    pull = lambda t: np.sin(np.pi * np.minimum(t * 1.15, 1)) ** 1.4
    place(mix, strand(1.55, 1700, 600, -0.1, -0.95, seed, pull), 0.0, 0.6)
    place(mix, strand(1.55, 1900, 650, 0.1, 0.95, seed + 1, pull), 0.03, 0.6)
    for i, note in enumerate((D7, B6, A6, Fs6)):
        place(mix, glass(note, 0.8, decay=0.14, brightness=0.5), 0.12 + i * 0.13, 0.16 - i * 0.02,
              (0.3 + i * 0.18) * (1 if i % 2 else -1))
    # A breath gathering where the heart is about to bloom.
    place(mix, air(0.9, 400, 1400, q=1.2, seed=seed + 2, shape=lambda t: np.sin(np.pi * t * 0.5) ** 2), 0.75, 0.22)


def helix_departure() -> np.ndarray:
    """The departure on its own, for listening only (not bundled): match and
    no-match start with it, so it stays in time with the heart."""
    mix = silence(2.6)
    departure(mix, 121)
    return finish(reverb(mix, 2.0, 0.4), -8.0)


def first_name() -> np.ndarray:
    """A first name is saved: a quick sweep of stardust, as if the name were
    written in light."""
    mix = silence(2.0)
    rng = np.random.default_rng(131)
    scale = [D6, E6, Fs6, A6, B6, D7, E7, Fs7, A7]
    for i in range(16):
        x = i / 15
        note = scale[min(len(scale) - 1, int(x * len(scale)))]
        place(mix, glass(note, 0.7, decay=rng.uniform(0.1, 0.2), brightness=0.5, attack=0.002),
              0.42 * x ** 0.9 + rng.uniform(0, 0.012), 0.22 + 0.12 * math.sin(math.pi * x), -0.7 + 1.4 * x)
    place(mix, air(0.6, 1200, 4200, q=1.6, seed=132), 0.0, 0.18)
    place(mix, glass(A6, 1.4, decay=0.5, brightness=0.8), 0.46, 0.3, 0.2)
    return finish(reverb(mix, 1.9, 0.4), -9.0)


AMBIENCE_SECONDS = 24


def ambience() -> np.ndarray:
    """The landing page's bed under the turning heart: a breathing, open D
    chord with a whisper of air and the odd far-off star.

    Everything is periodic in exactly 24 s (sine frequencies on whole cycles,
    air and reverb made circularly), so it loops without a seam."""
    n = AMBIENCE_SECONDS * SR
    t = np.arange(n) / SR
    out = np.zeros((n, 2))
    period = AMBIENCE_SECONDS

    def whole(f: float) -> float:
        return round(f * period) / period

    # Slow swells; every LFO completes whole cycles within the loop.
    voices = [(D4, 0.5, 1, 0.0), (A4, 0.42, 2, 1.3), (E5, 0.28, 3, 2.1), (Fs5, 0.18, 1, 4.0),
              (A5, 0.16, 2, 0.7), (Cs6, 0.07, 3, 3.3)]
    rng = np.random.default_rng(141)
    for note, amp, cycles, offset in voices:
        swell = 0.55 + 0.45 * np.sin(2 * math.pi * cycles * t / period + offset)
        for detune, pan in ((-0.0035, -0.5), (0.0035, 0.5)):
            f = whole(midi(note) * (1 + detune))
            phase = 2 * math.pi * f * t + rng.random() * 6
            tone = np.sin(phase) + 0.08 * np.sin(2 * phase)
            left = math.cos((pan + 1) * math.pi / 4)
            right = math.sin((pan + 1) * math.pi / 4)
            out[:, 0] += tone * swell * amp * left
            out[:, 1] += tone * swell * amp * right

    # Air: noise shaped in the frequency domain, so it is periodic by design.
    freqs = np.fft.rfftfreq(n, 1 / SR)
    shape = np.exp(-0.5 * ((np.log(np.maximum(freqs, 1)) - math.log(1600)) / 0.5) ** 2)
    breathe = 0.6 + 0.4 * np.sin(2 * math.pi * 2 * t / period + 1.0)
    for ch in range(2):
        spectrum = shape * np.exp(2j * math.pi * rng.random(len(freqs)))
        noise = np.fft.irfft(spectrum, n)
        out[:, ch] += noise / np.std(noise) * 0.035 * breathe

    # A few distant stars, wrapping around the loop point.
    stars = silence(AMBIENCE_SECONDS + 2)
    for at, note, pan in ((2.7, A6, -0.6), (7.9, Fs6, 0.5), (11.4, D7, -0.2), (16.3, E6, 0.65),
                          (19.8, B6, -0.45), (22.6, A6, 0.3)):
        place(stars, glass(note, 1.6, decay=0.5, brightness=0.5), at, 0.09, pan)
    out += stars[:n]
    out[: len(stars) - n] += stars[n:]

    # Circular reverb, so the tail also wraps into the start.
    wet = np.zeros_like(out)
    tail = int(3.5 * SR)
    for ch in range(2):
        noise = rng.standard_normal(tail)
        ir = np.convolve(noise, np.ones(10) / 10, mode="same") * np.exp(-6.9 * np.arange(tail) / tail)
        ir /= np.sqrt(np.sum(ir ** 2))
        padded = np.zeros(n)
        padded[:tail] = ir
        wet[:, ch] = np.fft.irfft(np.fft.rfft(out[:, ch]) * np.fft.rfft(padded), n)
    out = out * 0.7 + wet * 0.5
    out -= out.mean(axis=0)
    return out / np.max(np.abs(out)) * 10 ** (-6 / 20)


def match() -> np.ndarray:
    """A match: the heart blooms in a luminous chord and keeps glittering."""
    mix = silence(5.6)
    departure(mix, 31)
    place(mix, pad([D4, A4, Fs5, Cs6], 3.6, attack=0.4, release=1.6, level=0.42), 1.5)
    for note, at, pan in ((D5, 1.58, -0.2), (A5, 1.62, 0.2), (Fs6, 1.68, -0.35), (A6, 1.74, 0.35), (E7, 1.86, 0.0)):
        place(mix, glass(note, 3.0, decay=1.1), at, 0.34, pan)
    place(mix, sparkles(2.6, 20, seed=33, density=lambda x: x ** 1.5, level=0.38), 1.7)
    return finish(reverb(mix, 3.0, 0.45), -4.5)


def no_match() -> np.ndarray:
    """No match: an open, unresolved chord that drifts gently down as the
    heart lets go. Kind, never a 'fail' sound."""
    mix = silence(7.0)
    departure(mix, 41)
    place(mix, pad([D4, A4, E5], 3.2, attack=0.5, release=1.6, level=0.36), 1.5)
    for note, at, pan in ((D5, 1.6, -0.2), (A5, 1.66, 0.2), (E6, 1.74, 0.0)):
        place(mix, glass(note, 2.6, decay=0.9, brightness=0.7), at, 0.3, pan)
    for i, note in enumerate((B5, A5, Fs5)):
        place(mix, glass(note, 2.0, decay=0.7, brightness=0.55), 4.5 + i * 0.17, 0.26 - i * 0.04, 0.4 - i * 0.4)
    return finish(reverb(mix, 3.2, 0.48), -6.5)


def unfold() -> np.ndarray:
    """A saved match unfolds in place from the helix (2.2 s)."""
    mix = silence(4.4)
    place(mix, air(2.2, 500, 2200, q=1.6, seed=51, shape=lambda t: np.sin(np.pi * t) ** 2), 0.0, 0.42)
    place(mix, pad([D4, A4, Fs5], 2.6, attack=1.2, release=1.2, level=0.36), 0.2)
    for note, at, pan in ((Fs6, 2.05, -0.25), (A6, 2.12, 0.25)):
        place(mix, glass(note, 2.0, decay=0.8), at, 0.32, pan)
    return finish(reverb(mix, 2.6, 0.42), -7.0)


def exchange() -> np.ndarray:
    """Two phones meet: notes passing back and forth between them."""
    mix = silence(2.0)
    place(mix, air(1.2, 900, 2400, q=2.2, seed=61), 0.0, 0.25)
    for i, (note, pan) in enumerate(((A5, -0.7), (D6, 0.7), (A6, -0.5), (D7, 0.5), (Fs7, 0.0))):
        place(mix, glass(note, 1.3, decay=0.45, brightness=0.75), 0.06 + i * 0.075, 0.42 - i * 0.04, pan)
    return finish(reverb(mix, 2.0, 0.38), -7.0)


def chat_open() -> np.ndarray:
    """The heart's tip lifts into two rings: air rising, then two chimes."""
    mix = silence(3.0)
    place(mix, air(1.6, 380, 2600, q=1.5, seed=71, shape=lambda t: np.sin(np.pi * t * 0.8) ** 2), 0.0, 0.42)
    place(mix, glass(Fs6, 1.6, decay=0.6), 1.0, 0.36, -0.4)
    place(mix, glass(A6, 1.6, decay=0.6), 1.12, 0.36, 0.4)
    return finish(reverb(mix, 2.2, 0.4), -7.5)


def message_sent() -> np.ndarray:
    """A message leaves: a small bubble rising."""
    mix = silence(0.6)
    place(mix, soft_tone(A5, 0.32, decay=0.07, attack=0.004, glide=7), 0.0, 0.75)
    place(mix, glass(E7, 0.4, decay=0.06, brightness=0.4), 0.05, 0.12)
    return finish(reverb(mix, 0.9, 0.22), -12.0)


def message_received() -> np.ndarray:
    """A message arrives: two notes of glass, a fourth apart."""
    mix = silence(1.2)
    place(mix, glass(E6, 1.0, decay=0.3, brightness=0.8), 0.0, 0.6, -0.2)
    place(mix, glass(A6, 1.1, decay=0.38, brightness=0.8), 0.09, 0.55, 0.2)
    return finish(reverb(mix, 1.4, 0.32), -9.0)


def lock() -> np.ndarray:
    """A tap on the lock: a small, muffled bell, like knocking on glass."""
    mix = silence(0.8)
    place(mix, glass(D5, 0.8, decay=0.09, brightness=0.25, attack=0.002), 0.0, 0.9)
    place(mix, soft_tone(D4, 0.3, decay=0.05, attack=0.002), 0.0, 0.5)
    return finish(reverb(mix, 0.9, 0.24), -11.0)


def open_() -> np.ndarray:
    """Something opens or comes forward: a short breath of air upwards."""
    mix = silence(1.1)
    place(mix, air(0.55, 520, 2300, q=1.3, seed=81, shape=lambda t: np.sin(np.pi * t) ** 1.5), 0.0, 0.8)
    place(mix, glass(A6, 0.7, decay=0.16, brightness=0.4), 0.36, 0.12)
    return finish(reverb(mix, 1.2, 0.3), -14.0)


def close() -> np.ndarray:
    """Something closes or steps back: the same breath, falling."""
    mix = silence(1.1)
    place(mix, air(0.5, 2200, 480, q=1.3, seed=91, shape=lambda t: np.sin(np.pi * t) ** 1.5), 0.0, 0.8)
    place(mix, glass(D6, 0.7, decay=0.14, brightness=0.35), 0.3, 0.1)
    return finish(reverb(mix, 1.2, 0.3), -15.0)


def success() -> np.ndarray:
    """Signed in, or a moment of success: stars twinkling upward."""
    mix = silence(1.8)
    for i, note in enumerate((A5, D6, Fs6, A6, D7)):
        place(mix, glass(note, 1.2, decay=0.42, brightness=0.8), i * 0.05, 0.5 - i * 0.05, -0.6 + i * 0.3)
    place(mix, sparkles(0.6, 5, seed=101, level=0.3), 0.25)
    return finish(reverb(mix, 1.8, 0.38), -8.0)


def swish() -> np.ndarray:
    """Switching between personality tests: the same breath as `open`, but
    lighter and passing sideways, as if the chart were turned like a page."""
    mix = silence(0.8)
    shape = lambda t: np.sin(np.pi * t) ** 1.8
    place(mix, strand(0.42, 900, 2600, -0.55, 0.55, 151, shape), 0.0, 0.85)
    return finish(reverb(mix, 0.9, 0.22), -17.0)


def toggle(on: bool) -> np.ndarray:
    """A switch slides: a soft knock of the thumb and a small glass note,
    a fifth up when it turns on and back down when it turns off."""
    mix = silence(0.6)
    first, second = (A5, E6) if on else (E6, A5)
    place(mix, soft_tone(D4 + 12, 0.08, decay=0.012, attack=0.001), 0.0, 0.35)
    place(mix, glass(first, 0.35, decay=0.05, brightness=0.4, attack=0.002, shimmer=0.0004), 0.0, 0.55)
    place(mix, glass(second, 0.45, decay=0.09, brightness=0.45, attack=0.002, shimmer=0.0004), 0.045, 0.7)
    return finish(reverb(mix, 0.7, 0.18), -15.0)


def tick() -> np.ndarray:
    """One notch of a wheel, ruler or slider: the faintest dry tick, quieter
    than `select` because it can fire many times a second."""
    mix = silence(0.25)
    place(mix, glass(E7, 0.12, decay=0.012, brightness=0.3, attack=0.0008, shimmer=0.0), 0.0, 1.0)
    place(mix, soft_tone(A5, 0.05, decay=0.006, attack=0.0008), 0.0, 0.25)
    return finish(reverb(mix, 0.25, 0.08), -22.0)


def notification() -> np.ndarray:
    """The app's signature. A rising four-note motif (A–D–A–F#) on glass,
    over a soft fifth, with one final star. Bright enough to carry on a
    phone speaker, and short."""
    mix = silence(2.6)
    place(mix, pad([D5, A5], 1.9, attack=0.08, release=1.2, level=0.5), 0.0)
    for note, at, gain, pan in ((A5, 0.0, 0.5, -0.25), (D6, 0.12, 0.52, 0.25),
                                (A6, 0.24, 0.62, -0.1), (Fs6, 0.5, 0.56, 0.15)):
        place(mix, glass(note, 1.8, decay=0.65, brightness=1.0), at, gain, pan)
    place(mix, glass(D7, 1.2, decay=0.35, brightness=0.6), 0.74, 0.22, 0.4)
    return finish(reverb(mix, 1.8, 0.34), -1.0)


CUES = {
    "entrance": entrance,
    "step-1": lambda: step(D6),
    "step-2": lambda: step(E6),
    "step-3": lambda: step(Fs6),
    "step-4": lambda: step(A6),
    "step-5": lambda: step(B6),
    "select": select,
    "rejection": rejection,
    "seal": seal,
    "complete": complete,
    "match": match,
    "no-match": no_match,
    "unfold": unfold,
    "exchange": exchange,
    "chat-open": chat_open,
    "message-sent": message_sent,
    "message-received": message_received,
    "lock": lock,
    "open": open_,
    "close": close,
    "success": success,
    "notification-chime": notification,
    "helix-arrival": helix_arrival,
    "name": first_name,
    "ambience": ambience,
    "swish": swish,
    "toggle-on": lambda: toggle(True),
    "toggle-off": lambda: toggle(False),
    "tick": tick,
}


NOTIFICATION = "notification-chime"
# Looped sample-accurately, so kept in a CAF whose packet table records the
# AAC priming exactly.
AMBIENCE = "ambience"


def write(name: str, sound: np.ndarray) -> None:
    pcm = (np.clip(sound, -1, 1) * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, f"{name}.wav")
        with wave.open(wav, "wb") as f:
            f.setnchannels(2)
            f.setsampwidth(2)
            f.setframerate(SR)
            f.writeframes(pcm.tobytes())
        if name == NOTIFICATION:
            # Notification sounds must be linear PCM (or IMA4/aLaw/µLaw).
            target = os.path.join(OUT, f"{name}.caf")
            command = ["afconvert", "-f", "caff", "-d", f"LEI16@{SR}", wav, target]
        elif name == AMBIENCE:
            target = os.path.join(OUT, f"{name}.caf")
            command = ["afconvert", "-f", "caff", "-d", "aac", "-b", "128000", "-q", "127", wav, target]
        else:
            target = os.path.join(OUT, f"{name}.m4a")
            command = ["afconvert", "-f", "m4af", "-d", "aac", "-b", "160000", "-q", "127", wav, target]
        subprocess.run(command, check=True)
    rms = 20 * np.log10(np.sqrt(np.mean(sound ** 2)) + 1e-12)
    print(f"{name:20s} {len(sound) / SR:5.2f}s  rms {rms:6.1f} dBFS")


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    for name, make in CUES.items():
        if only and name not in only:
            continue
        write(name, make())


if __name__ == "__main__":
    main()
