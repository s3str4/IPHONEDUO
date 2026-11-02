#!/usr/bin/env python3
"""Sons et musiques de Route de Nuit, entièrement synthétisés (aucun échantillon
externe) : assets/audio/*.ogg.

    python3 tools/make_audio.py

Boucles sans couture (moteur, pluie, vent, pneus, musiques : rendu circulaire,
ce qui déborde de la fin revient au début), bruitages ponctuels, et deux
stations de radio : synthwave (104 bpm) et lo-fi (78 bpm). Déterministe.
Dépendances : numpy, ffmpeg (encodage Ogg Vorbis).
"""
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"
rng = np.random.default_rng(1984)


# --- Outils -----------------------------------------------------------------

def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def fft_filter(x, lo=None, hi=None):
    """Filtre passe-bande idéal adouci, par FFT (rapide pour les longs signaux)."""
    n = len(x)
    spec = np.fft.rfft(x, axis=0)
    f = np.fft.rfftfreq(n, 1 / SR)
    gain = np.ones_like(f)
    if lo:
        gain *= 1 / (1 + (lo / np.maximum(f, 1e-3)) ** 4)
    if hi:
        gain *= 1 / (1 + (f / hi) ** 4)
    if spec.ndim == 2:
        gain = gain[:, None]
    return np.fft.irfft(spec * gain, n, axis=0)


def saw(freq, t, harmonics=24):
    """Dent de scie à bande limitée."""
    out = np.zeros_like(t)
    for k in range(1, harmonics + 1):
        if freq * k > SR / 2.2:
            break
        out += np.sin(2 * np.pi * freq * k * t) / k
    return out * 0.6


def square(freq, t, harmonics=15):
    out = np.zeros_like(t)
    for k in range(1, harmonics + 1, 2):
        if freq * k > SR / 2.2:
            break
        out += np.sin(2 * np.pi * freq * k * t) / k
    return out * 0.8


def env(n, attack, decay, sustain=0.0, release=None):
    """Enveloppe : attaque, décroissance exponentielle vers sustain."""
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(attack, 1e-4))
    e *= sustain + (1 - sustain) * np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4))
    if release:
        e *= np.clip((n / SR - t) / release, 0, 1)
    return e


def place(track, sound, start, gain=1.0, pan=0.0):
    """Ajoute un son dans une piste stéréo circulaire (le débordement revient au début)."""
    n = len(track)
    i = int(start * SR) % n
    left = np.sqrt(0.5 * (1 - pan)) * gain
    right = np.sqrt(0.5 * (1 + pan)) * gain
    idx = (np.arange(len(sound)) + i) % n
    np.add.at(track[:, 0], idx, sound * left)
    np.add.at(track[:, 1], idx, sound * right)


def reverb(x, seconds=1.6, mix=0.25, seed=3):
    """Réverbération par convolution avec un bruit à décroissance exponentielle (circulaire)."""
    r = np.random.default_rng(seed)
    n = int(SR * seconds)
    ir = r.normal(0, 1, (n, 2)) * np.exp(-np.arange(n) / (SR * seconds / 6))[:, None]
    ir = fft_filter(ir, lo=200, hi=6000)
    ir /= np.sqrt((ir ** 2).sum(axis=0))
    m = len(x)
    wet = np.fft.irfft(np.fft.rfft(x, axis=0) * np.fft.rfft(ir, m, axis=0), m, axis=0)
    return x * (1 - mix) + wet * mix * 2.0


def note_freq(name_or_midi):
    return 440.0 * 2 ** ((name_or_midi - 69) / 12)


def save(name, data, loop=False):
    data = np.asarray(data, np.float64)
    peak = np.max(np.abs(data)) or 1.0
    data = data / peak * 0.8
    if data.ndim == 1:
        data = data[:, None]
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / "s.wav"
        with wave.open(str(wav_path), "wb") as w:
            w.setnchannels(data.shape[1])
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes((np.clip(data, -1, 1) * 32767).astype("<i2").tobytes())
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav_path), "-c:a", "libvorbis",
                        "-q:a", "4", str(OUT / f"{name}.ogg")], check=True)
    print(f"{name}.ogg  {len(data) / SR:.1f} s{'  (boucle)' if loop else ''}")


def seamless(x, fade=0.2):
    """Boucle sans couture : fondu enchaîné de la fin sur le début."""
    n = int(SR * fade)
    head = x[:n].copy()
    tail = x[-n:]
    ramp = np.linspace(0, 1, n)
    if x.ndim == 2:
        ramp = ramp[:, None]
    out = x[:-n].copy()
    out[:n] = head * ramp + tail * (1 - ramp)
    return out


# --- Moteur, ambiances -----------------------------------------------------------

def engine(f0, seconds, bright):
    """Boucle de moteur : harmoniques du régime (nombre entier de cycles), un peu
    de grain, saturée. f0 × seconds doit être entier."""
    t = t_axis(seconds)
    x = np.zeros_like(t)
    weights = {1: 1.0, 2: 0.8, 3: 0.35, 4: 0.6, 6: 0.3, 8: 0.25}
    for k in range(1, 40):
        w = weights.get(k, 0.12 * bright / k ** 0.6)
        x += w * np.sin(2 * np.pi * f0 * k * t + rng.uniform(0, 6.28))
    # Explosions irrégulières : modulation d'amplitude au rythme des cylindres.
    x *= 1 + 0.25 * np.sin(2 * np.pi * f0 * 0.5 * t) + 0.05 * rng.normal(0, 1, len(t))
    x = np.tanh(x * (1.2 + bright))
    return x


def noise_loop(seconds, lo, hi, seed):
    r = np.random.default_rng(seed)
    x = r.normal(0, 1, int(SR * (seconds + 0.3)))
    return seamless(fft_filter(x, lo, hi), 0.3)


def rain_loop(seconds=8.0):
    base = noise_loop(seconds, 400, 9000, 11) * 0.5
    # Gouttes : petits clics filtrés.
    r = np.random.default_rng(12)
    drops = np.zeros(len(base))
    for _ in range(int(seconds * 90)):
        i = r.integers(0, len(drops) - 400)
        drops[i:i + 400] += r.uniform(0.2, 1) * np.exp(-np.arange(400) / 40) * r.normal(0, 1, 400)
    drops = fft_filter(drops, 1500, 12000)
    return base + drops * 0.6


# --- Bruitages ---------------------------------------------------------------

def crash():
    t = t_axis(1.2)
    thump = np.sin(2 * np.pi * (70 * t - 30 * t ** 2)) * np.exp(-t / 0.18)
    crunch = fft_filter(rng.normal(0, 1, len(t)), 300, 6000) * np.exp(-t / 0.12)
    clink = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / 0.35) for f in (1730, 2410, 3150)) * 0.15
    return thump * 1.0 + crunch * 0.7 + clink


def whoosh():
    t = t_axis(0.7)
    n = fft_filter(rng.normal(0, 1, len(t)), 500, 5000)
    shape = np.exp(-((t - 0.25) / 0.12) ** 2)
    # Effet Doppler grossier : le bruit est filtré de plus en plus bas.
    return fft_filter(n * shape, 300, 3500) + n * shape * 0.3


def chime():
    t = t_axis(1.8)
    out = np.zeros_like(t)
    for start, f in ((0.0, note_freq(84)), (0.16, note_freq(91))):
        tt = np.clip(t - start, 0, None)
        e = (t >= start) * np.exp(-tt / 0.5)
        out += e * (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * f * 2.76 * tt))
    return out


def static_burst():
    t = t_axis(0.45)
    n = fft_filter(rng.normal(0, 1, len(t)), 800, 7000)
    crackle = (rng.random(len(t)) > 0.995) * rng.normal(0, 3, len(t))
    return (n * 0.5 + crackle) * env(len(t), 0.01, 0.15, 0.2, 0.1)


def thud():
    t = t_axis(0.9)
    return np.sin(2 * np.pi * (55 * t - 20 * t ** 2)) * np.exp(-t / 0.25) \
        + fft_filter(rng.normal(0, 1, len(t)), 80, 900) * np.exp(-t / 0.1) * 0.8


def thunder():
    """Tonnerre : un craquement sec, puis un grondement grave qui roule."""
    t = t_axis(4.5)
    crack = fft_filter(rng.normal(0, 1, len(t)), 400, 6000) * np.exp(-t / 0.08) * 0.6
    rumble = fft_filter(rng.normal(0, 1, len(t)), 25, 260)
    swell = (1 - np.exp(-t / 0.3)) * np.exp(-t / 1.6) * (1 + 0.4 * np.sin(2 * np.pi * 1.3 * t))
    return crack + rumble * swell * 3.0


def blip():
    t = t_axis(0.25)
    return np.sin(2 * np.pi * (660 + 400 * t) * t) * env(len(t), 0.005, 0.08)


# --- Musique ----------------------------------------------------------------------

def kick(gain=1.0):
    t = t_axis(0.4)
    f = 45 + 80 * np.exp(-t / 0.03)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.18) * gain


def snare(gain=1.0):
    t = t_axis(0.35)
    return (fft_filter(rng.normal(0, 1, len(t)), 1200, 9000) * np.exp(-t / 0.09)
            + np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.05) * 0.6) * gain


def hat(gain=1.0):
    t = t_axis(0.06)
    return fft_filter(rng.normal(0, 1, len(t)), 7000, None) * np.exp(-t / 0.015) * gain


def synthwave():
    bpm = 104
    beat = 60 / bpm
    bars = 32
    length = bars * 4 * beat
    track = np.zeros((int(SR * length), 2))
    # Am F C G, deux mesures chacun ; notes MIDI des accords (fondamentale, tierce, quinte, octave).
    prog = [[57, 60, 64, 69], [53, 57, 60, 65], [48, 52, 55, 60], [55, 59, 62, 67]]
    melody = [76, 74, 72, 74, 76, 79, 76, 74, 72, 71, 72, 74, 72, 69, 67, 69]
    for bar in range(bars):
        chord = prog[(bar // 2) % 4]
        t0 = bar * 4 * beat
        section = "intro" if bar < 8 else ("break" if 24 <= bar < 28 else "main")
        # Nappe : trois scies désaccordées par note, attaque lente.
        if bar % 2 == 0:
            n = int(SR * 8 * beat)
            tt = np.arange(n) / SR
            pad = np.zeros(n)
            for m in chord[:3]:
                for det in (-0.004, 0.0, 0.004):
                    pad += saw(note_freq(m) * (1 + det), tt, 10)
            pad = fft_filter(pad, 120, 2200) * env(n, 0.8, 8.0, 0.8, 1.0)
            place(track, pad, t0, 0.10, -0.3)
            place(track, pad, t0 + 0.012, 0.10, 0.3)
        # Basse : croches sur la fondamentale, une octave sous.
        for i in range(8):
            n = int(SR * beat * 0.48)
            tt = np.arange(n) / SR
            b = fft_filter(saw(note_freq(chord[0] - 12), tt, 18), None, 900) * env(n, 0.005, 0.12, 0.3, 0.02)
            place(track, b, t0 + i * beat / 2, 0.35 if section != "break" else 0.15)
        # Arpège en doubles croches avec écho stéréo.
        if section != "intro" or bar >= 4:
            for i in range(16):
                m = chord[[0, 1, 2, 3, 2, 1, 2, 3][i % 8]] + 12
                n = int(SR * beat * 0.24)
                tt = np.arange(n) / SR
                a = square(note_freq(m), tt, 9) * env(n, 0.003, 0.06, 0.0)
                st = t0 + i * beat / 4
                place(track, a, st, 0.05, -0.5)
                place(track, a, st + beat * 0.75, 0.025, 0.6)
        # Batterie.
        if section == "main" or bar >= 28:
            for i in range(4):
                place(track, kick(), t0 + i * beat, 0.7)
                if i in (1, 3):
                    place(track, snare(), t0 + i * beat, 0.35)
            for i in range(8):
                place(track, hat(), t0 + i * beat / 2, 0.12 if i % 2 else 0.07, 0.3)
        # Mélodie en sections principales.
        if 12 <= bar < 24:
            for i in range(2):
                m = melody[((bar - 12) * 2 + i) % len(melody)]
                n = int(SR * beat * 1.9)
                tt = np.arange(n) / SR
                vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * tt) * np.clip(tt / 0.3, 0, 1)
                lead = (saw(note_freq(m), tt * vib, 8) * 0.6 + np.sin(2 * np.pi * note_freq(m) * tt * vib)) \
                    * env(n, 0.02, 1.2, 0.5, 0.2)
                place(track, fft_filter(lead, None, 3500), t0 + i * 2 * beat, 0.12, 0.1)
    return reverb(track, 1.8, 0.28)


def lofi():
    bpm = 78
    beat = 60 / bpm
    bars = 16
    length = bars * 4 * beat
    track = np.zeros((int(SR * length), 2))
    # Dm9 G13 Cmaj9 Am9.
    prog = [[50, 53, 57, 60, 64], [43, 53, 57, 59, 64], [48, 52, 55, 59, 62], [45, 55, 60, 64, 67]]
    swing = beat * 0.08
    for bar in range(bars):
        chord = prog[bar % 4]
        t0 = bar * 4 * beat
        # Piano électrique : sinusoïdes avec partiels de cloche et trémolo.
        for hit, dur in ((0.0, 2.5), (2.5, 1.5)):
            n = int(SR * beat * dur)
            tt = np.arange(n) / SR
            ep = np.zeros(n)
            for m in chord[1:]:
                f = note_freq(m)
                ep += np.sin(2 * np.pi * f * tt) + 0.25 * np.sin(2 * np.pi * f * 2 * tt) * np.exp(-tt / 0.3)
            ep *= (1 + 0.15 * np.sin(2 * np.pi * 4.5 * tt)) * env(n, 0.01, 1.5, 0.3, 0.3)
            place(track, ep, t0 + hit * beat, 0.07, -0.2)
        # Contrebasse feutrée.
        for i, step in enumerate((0, 1.5, 2, 3.5)):
            n = int(SR * beat * 0.9)
            tt = np.arange(n) / SR
            m = chord[0] - 12 if i % 2 == 0 else chord[0] - 5
            bs = np.sin(2 * np.pi * note_freq(m) * tt) * env(n, 0.01, 0.4, 0.2, 0.1)
            place(track, bs, t0 + step * beat, 0.3)
        # Batterie molle, chaloupée.
        for i in range(4):
            place(track, fft_filter(kick(), None, 1200), t0 + i * beat, 0.5 if i in (0, 2) else 0.0)
            if i in (1, 3):
                place(track, fft_filter(snare(), None, 4000), t0 + i * beat, 0.18)
        for i in range(8):
            place(track, hat(), t0 + i * beat / 2 + (swing if i % 2 else 0), 0.05)
    # Craquements de vinyle.
    crackle = (rng.random(len(track)) > 0.9993) * rng.normal(0, 1, len(track))
    track += fft_filter(np.stack([crackle, np.roll(crackle, 37)], 1), 1000, 8000) * 0.05
    track = fft_filter(track, 40, 5500)
    return reverb(track, 1.4, 0.22)


def main():
    # Moteur : passe-bas pour garder le grondement et la montée, sans grésillement.
    save("engine_low", fft_filter(engine(40.0, 2.0, 0.2), None, 1400) * 0.9, loop=True)
    save("engine_high", fft_filter(engine(80.0, 2.0, 0.6), 60, 3800) * 0.9, loop=True)
    save("rain", rain_loop(), loop=True)
    save("wind", noise_loop(6.0, 80, 1200, 21), loop=True)
    save("tires", noise_loop(4.0, 1500, 9000, 22), loop=True)
    save("crash", crash())
    save("whoosh", whoosh())
    save("chime", chime())
    save("static", static_burst())
    save("thud", thud())
    save("blip", blip())
    save("thunder", thunder())
    save("music_synthwave", synthwave(), loop=True)
    save("music_lofi", lofi(), loop=True)


if __name__ == "__main__":
    main()
