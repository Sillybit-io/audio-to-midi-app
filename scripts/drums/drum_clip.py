"""A short synthetic drum pattern used as the test clip for both drum models: 4 s, 44.1 kHz, mono, 16-bit."""
import wave

import numpy as np

RATE = 44100
SECONDS = 4.0


def _decay(n, tau):
    return np.exp(-np.arange(n) / RATE / tau)


def _kick(rs):
    n = int(0.35 * RATE)
    t = np.arange(n) / RATE
    phase = 2 * np.pi * (50 * t + 100 * (1 - np.exp(-t / 0.03)) * 0.03)
    return 0.9 * np.sin(phase) * _decay(n, 0.09)


def _snare(rs):
    n = int(0.3 * RATE)
    t = np.arange(n) / RATE
    return (0.5 * np.sin(2 * np.pi * 190 * t) * _decay(n, 0.05) + 0.6 * rs.randn(n) * _decay(n, 0.07)) * 0.8


def _hat(rs, open_=False):
    n = int((0.25 if open_ else 0.06) * RATE)
    noise = rs.randn(n)
    noise = np.diff(noise, prepend=0)  # crude high-pass
    return 0.35 * noise * _decay(n, 0.12 if open_ else 0.02)


def _tom(rs, freq):
    n = int(0.4 * RATE)
    t = np.arange(n) / RATE
    return 0.8 * np.sin(2 * np.pi * freq * t * (1 + 0.15 * np.exp(-t / 0.04))) * _decay(n, 0.12)


def make_clip():
    rs = np.random.RandomState(7)
    clip = np.zeros(int(SECONDS * RATE) + RATE // 2)

    def hit(sound, at, gain=1.0):
        a = int(at * RATE)
        clip[a:a + len(sound)] += gain * sound

    beat = 0.5
    for bar in range(2):
        start = bar * 4 * beat * 1.0
        for b in range(4):
            hit(_kick(rs), start + b * beat, 1.0 if b % 2 == 0 else 0.8)
        for b in (1, 3):
            hit(_snare(rs), start + b * beat, 1.0)
        for e in range(8):
            hit(_hat(rs), start + e * beat / 2, 0.9 if e % 2 == 0 else 0.5)
    hit(_tom(rs, 120), 3.5)
    hit(_tom(rs, 90), 3.7)
    clip = clip[: int(SECONDS * RATE)]
    return (0.8 * clip / np.abs(clip).max()).astype(np.float32)


def write_wav(path, clip):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(clip, -1, 1) * 32767).astype("<i2").tobytes())
