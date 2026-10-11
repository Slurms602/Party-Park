#!/usr/bin/env python3
"""Render the game's music to game/assets/music/*.ogg (needs numpy and oggenc).

Everything is synthesized: FM electric piano and vibes, additive bass, leads and strings, synth drums, and an
FFT-convolution reverb. Same layout as Super Battle Golf's music: a menu theme, a match theme with a faster
"hurry" version for the final stretch, and a results jingle.

    python3 tools/make_music.py
"""
import os
import subprocess
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "music")
rng = np.random.default_rng(7)


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


class Track:
    def __init__(self, bpm, bars, tail=3.0):
        self.bpm = bpm
        self.step = 60.0 / bpm / 4  # one 16th note
        self.length = int(bars * 16 * self.step * SR)
        self.buf = np.zeros((self.length + int(tail * SR), 2))
        self.send = np.zeros_like(self.buf)  # reverb send
        self.duck = np.ones(len(self.buf))  # sidechain gain, written by the kick
        self.ducked = np.zeros_like(self.buf)  # layers that pump with the kick

    def t(self, bar, step, swing=0.0):
        s = bar * 16 + step
        if swing and int(s) % 2 == 1:
            s += swing
        return int(s * self.step * SR)

    def add(self, sig, at, pan=0.0, gain=1.0, verb=0.15, duck=False):
        end = min(at + len(sig), len(self.buf))
        sig = sig[: end - at] * gain
        lr = np.array([np.sqrt(0.5 - pan * 0.5), np.sqrt(0.5 + pan * 0.5)])
        target = self.ducked if duck else self.buf
        target[at:end] += sig[:, None] * lr
        self.send[at:end] += sig[:, None] * lr * verb

    def render(self, room=1.8, verb_gain=0.9):
        self.buf += self.ducked * self.duck[:, None]
        self.buf += reverb(self.send, room) * verb_gain
        n = self.length
        out = self.buf[:n].copy()
        tail = self.buf[n:]
        out[: len(tail)] += tail  # wrap tails so the loop is seamless
        return out


# ------------------------------------------------------------------ instruments

def env(n, a=0.005, d=0.3, s=0.0, r=0.05, hold=None):
    t = np.arange(n) / SR
    hold = hold if hold is not None else n / SR
    e = np.where(t < a, t / a, s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    rel = np.clip(1 - (t - hold) / r, 0, 1)
    return e * np.where(t > hold, rel, 1)


def additive(freq, dur, bright, decay_bright=0.0, odd=False, partials=40, detune=0.0, vib=0.0, rel=0.08):
    n = int((dur + rel) * SR)
    t = np.arange(n) / SR
    f = freq * (1 + vib * 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.15) * 4, 0, 1))
    phase = 2 * np.pi * np.cumsum(f) / SR
    cutoff = freq * (1 + bright * np.exp(-t * decay_bright) if decay_bright else 1 + bright * np.ones(n))
    out = np.zeros(n)
    for k in range(1, partials + 1):
        if odd and k % 2 == 0:
            continue
        if freq * k > SR / 2.2:
            break
        amp = (1 / k) / np.sqrt(1 + (freq * k / cutoff) ** 4)
        out += amp * np.sin(k * phase * (1 + detune * (k % 3 - 1)))
    return out


def ep(m, dur, vel=1.0):  # FM electric piano
    n = int((dur + 0.4) * SR)
    t = np.arange(n) / SR
    f = hz(m)
    idx = 1.6 * np.exp(-t * 5) * vel + 0.2
    tone = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * t))
    tine = 0.25 * np.sin(2 * np.pi * f * 14 * t) * np.exp(-t * 40) * vel
    return (tone + tine) * env(n, 0.002, 1.2, 0.0, 0.25, hold=dur) * vel


def vibes(m, dur):
    n = int((dur + 1.0) * SR)
    t = np.arange(n) / SR
    f = hz(m)
    s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 4 * t) * np.exp(-t * 6)
    return s * np.exp(-t * 1.6) * (1 + 0.25 * np.sin(2 * np.pi * 5 * t)) * env(n, 0.002, 9, 1, 0.3, hold=dur + 0.6)


def bass(m, dur, bright=6.0):
    s = additive(hz(m), dur, bright, decay_bright=9.0, partials=25)
    return s * env(len(s), 0.004, 0.35, 0.6, 0.06, hold=dur) * 0.9


def lead(m, dur, bright=5.0):
    s = additive(hz(m), dur, bright, decay_bright=2.0, partials=30, vib=1.0) + \
        0.5 * additive(hz(m) * 1.003, dur, bright, decay_bright=2.0, partials=30)
    return s * env(len(s), 0.012, 0.6, 0.65, 0.08, hold=dur) * 0.6


def strings(m, dur):
    s = sum(additive(hz(m) * d, dur, 3.0, partials=14, rel=0.4) for d in (0.996, 1.0, 1.005))
    return s * env(len(s), 0.25, 2.0, 0.8, 0.4, hold=dur) * 0.35


def brass(m, dur):
    s = additive(hz(m), dur, 7.0, partials=30, vib=0.6) + additive(hz(m) * 1.004, dur, 6.0, partials=30)
    n = len(s)
    swell = np.clip(np.arange(n) / SR / 0.06, 0, 1)
    return s * swell * env(n, 0.03, 1.0, 0.8, 0.3, hold=dur) * 0.5


def pluck(m, dur):
    s = additive(hz(m), dur, 10.0, decay_bright=14.0, partials=30)
    return s * env(len(s), 0.002, 0.18, 0.0, 0.05, hold=dur)


def noise(n):
    return rng.standard_normal(n)


def hp(x, k=1):  # crude high-pass by differencing
    for _ in range(k):
        x = np.diff(x, prepend=0.0)
    return x


def lp(x, w=8):  # crude low-pass by moving average
    return np.convolve(x, np.ones(w) / w, mode="same")


def kick():
    n = int(0.4 * SR)
    t = np.arange(n) / SR
    f = 45 + 120 * np.exp(-t * 32)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)
    s[:60] += noise(60) * 0.3
    return np.tanh(s * 1.6)


def snare():
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    return hp(noise(n)) * 0.35 * np.exp(-t * 16) + np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25) * 0.6


def clap():
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    e = sum(np.where(t >= o, np.exp(-(t - o) * 90), 0) for o in (0, 0.011, 0.022)) + 0.6 * np.exp(-np.clip(t - 0.03, 0, None) * 14) * (t >= 0.03)
    return lp(hp(noise(n)), 3) * e * 0.5


def hat(open_=False):
    n = int((0.3 if open_ else 0.06) * SR)
    t = np.arange(n) / SR
    return lp(hp(noise(n), 2), 2) * 0.3 * np.exp(-t * (9 if open_ else 70))


def shaker():
    n = int(0.08 * SR)
    t = np.arange(n) / SR
    return lp(hp(noise(n), 2), 2) * 0.09 * np.sin(np.pi * np.clip(t / 0.08, 0, 1))


def crash():
    n = int(2.0 * SR)
    t = np.arange(n) / SR
    return lp(hp(noise(n), 2), 2) * 0.14 * np.exp(-t * 1.8)


def tom(m):
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    f = hz(m) * (1 + 0.5 * np.exp(-t * 20))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)


def riser(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    return lp(hp(noise(n)), 4) * (t / dur) ** 2 * 0.25


def reverb(x, room):
    n = int(room * SR)
    t = np.arange(n) / SR
    ir = np.stack([lp(noise(n), 6), lp(noise(n), 6)], 1) * np.exp(-t * 3.2 / room)[:, None]
    ir[: int(0.012 * SR)] = 0  # pre-delay
    ir /= np.sqrt((ir ** 2).sum(0))
    size = 1 << int(np.ceil(np.log2(len(x) + n)))
    out = np.fft.irfft(np.fft.rfft(x, size, axis=0) * np.fft.rfft(ir, size, axis=0), size, axis=0)
    return out[: len(x)] * 0.5


def kick_at(tr, at, gain=0.9):
    tr.add(kick(), at, gain=gain, verb=0.02)
    d = int(0.22 * SR)
    end = min(at + d, len(tr.duck))
    tr.duck[at:end] = np.minimum(tr.duck[at:end], 1 - 0.55 * np.exp(-np.arange(end - at) / SR * 12))


# ------------------------------------------------------------------ songs

def lounge():
    """Menu: 'Lane Lounge', a laid-back jazz-funk groove at 96 BPM."""
    tr = Track(96, 32)
    sw = 0.18
    chords = [(43, [58, 62, 65, 69]), (48, [58, 64, 69, 74]), (41, [57, 64, 67, 72]), (50, [53, 60, 64, 69]),
              (43, [58, 62, 65, 69]), (48, [58, 64, 69, 74]), (45, [55, 60, 64, 67]), (50, [54, 60, 65, 69])]
    melody = [
        [(0, 74, 2), (2, 77, 2), (4, 79, 4), (10, 77, 2), (12, 74, 4)],
        [(2, 76, 2), (4, 77, 2), (6, 79, 2), (8, 81, 6), (14, 79, 2)],
        [(0, 76, 4), (4, 72, 2), (6, 74, 2), (8, 76, 8)],
        [(2, 69, 2), (4, 72, 2), (6, 74, 2), (8, 77, 4), (12, 76, 4)],
        [(0, 74, 2), (2, 77, 2), (4, 81, 4), (10, 82, 2), (12, 81, 4)],
        [(0, 79, 2), (2, 77, 2), (4, 76, 2), (6, 74, 2), (8, 76, 8)],
        [(0, 76, 4), (4, 79, 2), (6, 76, 2), (8, 72, 4), (12, 69, 4)],
        [(0, 66, 2), (2, 69, 2), (4, 72, 2), (6, 74, 2), (8, 78, 4), (12, 77, 4)],
    ]
    bass_pat = [(0, 0, 3), (3, 12, 1), (6, 7, 2), (8, 0, 2), (11, 10, 1), (12, 12, 2), (14, 7, 2)]
    for bar in range(32):
        root, voicing = chords[bar % 8]
        sec = bar // 8
        for s in range(0, 16, 2):  # swung hats
            tr.add(hat(open_=(s == 14)), tr.t(bar, s, sw), pan=0.3, gain=1.2 if s % 4 else 0.8, verb=0.05)
        if sec > 0 or bar >= 4:
            for s in (0, 10):
                kick_at(tr, tr.t(bar, s), 0.6)
            for s in (4, 12):
                tr.add(snare(), tr.t(bar, s, sw), gain=0.35, verb=0.25)
        for s, off, ln in bass_pat:
            tr.add(bass(root + off, ln * tr.step * 0.9, bright=4.0), tr.t(bar, s, sw), gain=0.32, verb=0.03, duck=True)
        for s, ln, vel in ((0, 5, 0.9), (6, 2, 0.6), (10, 3, 0.7)):
            for i, m in enumerate(voicing):
                tr.add(ep(m, ln * tr.step, vel), tr.t(bar, s, sw) + i * 90, pan=-0.25 + i * 0.15, gain=0.07, verb=0.3)
        if sec in (1, 3):
            for s, m, ln in melody[bar % 8]:
                tr.add(vibes(m, ln * tr.step), tr.t(bar, s, sw), pan=0.15, gain=0.3, verb=0.45)
        if sec >= 2:
            for m in voicing[:3]:
                tr.add(strings(m, 16 * tr.step), tr.t(bar, 0), pan=-0.1, gain=0.1, verb=0.5, duck=True)
    return tr.render(room=2.2)


DISCO_CHORDS = [(45, [55, 59, 60, 64]), (45, [55, 59, 60, 64]), (50, [53, 57, 60, 64]), (50, [53, 57, 60, 64]),
                (41, [57, 60, 64, 67]), (43, [59, 62, 64, 67]), (40, [55, 59, 62, 67]), (40, [56, 62, 67, 71])]
DISCO_HOOK = [
    [(0, 76, 2), (2, 79, 2), (4, 81, 3), (7, 79, 1), (8, 76, 2), (10, 74, 2), (12, 76, 4)],
    [(0, 72, 2), (3, 74, 1), (4, 76, 4), (10, 79, 2), (12, 81, 2), (14, 83, 2)],
    [(0, 84, 4), (4, 81, 2), (6, 79, 2), (8, 77, 2), (10, 76, 2), (12, 77, 4)],
    [(0, 76, 2), (2, 74, 2), (4, 72, 4), (8, 69, 8)],
    [(0, 76, 2), (2, 79, 2), (4, 81, 3), (7, 79, 1), (8, 76, 2), (10, 81, 2), (12, 84, 4)],
    [(0, 83, 2), (2, 81, 2), (4, 79, 4), (8, 76, 2), (10, 79, 2), (12, 74, 4)],
    [(0, 79, 4), (4, 76, 2), (6, 74, 2), (8, 71, 4), (12, 74, 4)],
    [(0, 80, 2), (2, 79, 2), (4, 76, 2), (6, 74, 2), (8, 71, 2), (10, 68, 2), (12, 64, 4)],
]


def disco(bpm, bars, hurry=False):
    """Match: 'Strike Fever', disco-funk. hurry=True is the faster, busier final-stretch version."""
    tr = Track(bpm, bars)
    for bar in range(bars):
        root, voicing = DISCO_CHORDS[bar % 8]
        sec = bar // 8
        if bar % 8 == 0 and (bar > 0 or hurry):
            tr.add(crash(), tr.t(bar, 0), pan=-0.2, gain=0.7, verb=0.3)
        for s in range(0, 16, 4):
            kick_at(tr, tr.t(bar, s))
        for s in (4, 12):
            tr.add(clap(), tr.t(bar, s), pan=0.05, gain=0.8, verb=0.3)
        for s in range(16):
            if s % 4 == 2:
                tr.add(hat(open_=True), tr.t(bar, s), pan=0.25, gain=0.9, verb=0.05)
            elif hurry or s % 2 == 0:
                tr.add(hat(), tr.t(bar, s), pan=0.25, gain=0.6 if s % 2 else 0.9, verb=0.03)
            tr.add(shaker(), tr.t(bar, s), pan=-0.35, gain=0.8 if s % 2 else 0.5, verb=0.02)
        if bar % 4 == 3:  # tom fill into the next phrase
            for i, s in enumerate((12, 13, 14, 15) if hurry else (14, 15)):
                tr.add(tom(52 - i * 4), tr.t(bar, s), pan=0.4 - i * 0.25, gain=0.5, verb=0.2)
        for s in range(0, 16, 2):  # octave disco bass
            m = root + (12 if s % 4 == 2 else 0)
            if bar % 8 == 7 and s >= 12:
                m = root + [7, 10][(s - 12) // 2]
            tr.add(bass(m, tr.step * 1.6, bright=7.0), tr.t(bar, s), gain=0.45, verb=0.02, duck=True)
        for s in (2, 6, 10, 14):  # offbeat EP stabs
            for i, m in enumerate(voicing):
                tr.add(ep(m + 12, tr.step * 1.2, 0.8), tr.t(bar, s) + i * 40, pan=-0.35 + i * 0.1, gain=0.11, verb=0.2)
        if sec >= 1 or hurry:
            for m in voicing[1:]:
                tr.add(strings(m + 12, 16 * tr.step), tr.t(bar, 0), pan=0.2, gain=0.09, verb=0.4, duck=True)
        if sec in (1, 3) or (hurry and sec == 1):
            for s, m, ln in DISCO_HOOK[bar % 8]:
                tr.add(lead(m, ln * tr.step * 0.95, bright=9.0), tr.t(bar, s), pan=-0.1, gain=0.24, verb=0.3)
                tr.add(lead(m, ln * tr.step * 0.95) * 0.35, tr.t(bar, s) + int(tr.step * 3 * SR), pan=0.5, gain=0.2, verb=0.4)
        if sec == 2 or hurry:  # arpeggio layer
            arp = sorted(voicing + [voicing[0] + 12])
            for s in range(16):
                tr.add(pluck(arp[(s * 3) % len(arp)] + 12, tr.step * 0.8), tr.t(bar, s), pan=0.4 * np.sin(s), gain=0.07, verb=0.35)
        if hurry and bar == bars - 1:
            tr.add(riser(16 * tr.step), tr.t(bar, 0), gain=0.6, verb=0.2)
    return tr.render(room=1.6, verb_gain=0.7)


def victory():
    """Results: a short brass fanfare."""
    tr = Track(120, 6, tail=2.5)
    for i, s in enumerate(range(8, 16)):  # drum fill
        tr.add(snare() if i % 2 == 0 else tom(50 - i), tr.t(0, s), gain=0.5, verb=0.3)
    tr.add(crash(), tr.t(1, 0), gain=0.8, verb=0.4)
    kick_at(tr, tr.t(1, 0))
    seq = [(1, 0, [60, 64, 67], 4), (1, 4, [65, 69, 72], 2), (1, 6, [67, 71, 74], 2), (1, 8, [65, 69, 72], 2),
           (1, 10, [67, 71, 74], 2), (1, 12, [69, 72, 76], 4), (2, 0, [72, 76, 79], 24)]
    for bar, s, notes, ln in seq:
        for m in notes:
            tr.add(brass(m, ln * tr.step), tr.t(bar, s), gain=0.25, verb=0.4)
        tr.add(bass(notes[0] - 24, ln * tr.step), tr.t(bar, s), gain=0.5, verb=0.05)
    for i, m in enumerate([67, 72, 76, 79, 84]):
        tr.add(vibes(m, 0.6), tr.t(2, i), gain=0.25, verb=0.5)
    tr.add(crash(), tr.t(2, 0), gain=0.6, verb=0.4)
    kick_at(tr, tr.t(2, 0))
    out = tr.buf.copy()  # one-shot: keep the tail, don't wrap
    out += reverb(tr.send, 2.0) * 0.9
    return out[: int(5.5 * SR)] * np.linspace(1, 0, int(5.5 * SR))[:, None] ** 0.3


def master(x):
    for c in range(2):  # presence boost (~2-7 kHz) so leads and keys cut through; trim the boomy lows
        x[:, c] = x[:, c] + 1.6 * (lp(x[:, c], 3) - lp(x[:, c], 12)) - 0.25 * lp(x[:, c], 160)
    x = np.tanh(x * 1.3) / np.tanh(1.3)
    return x / np.abs(x).max() * 0.7  # headroom for Vorbis overshoot


def save(name, x):
    os.makedirs(OUT, exist_ok=True)
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((master(x) * 32767).astype("<i2").tobytes())
    subprocess.run(["oggenc", "-Q", "-q", "4", "-o", os.path.join(OUT, name + ".ogg"), wav], check=True)
    os.remove(wav)
    print(name, f"{len(x) / SR:.1f}s")


if __name__ == "__main__":
    save("menu", lounge())
    save("match", disco(120, 32))
    save("match_hurry", disco(132, 16, hurry=True))
    save("victory", victory())
