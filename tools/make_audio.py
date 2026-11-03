#!/usr/bin/env python3
"""Sons et musiques de Route de Nuit, entièrement synthétisés (aucun échantillon
externe) : assets/audio/*.ogg.

    python3 tools/make_audio.py

Boucles sans couture (moteur, pluie, vent, pneus, musiques : rendu circulaire,
ce qui déborde de la fin revient au début), bruitages ponctuels, et deux
stations de radio : synthwave (104 bpm) et lo-fi (78 bpm), et la musique de
l'aube des scènes de fin. Déterministe.
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


def siren():
    """Pin-pon de la gendarmerie, deux tons (la 435 Hz, ré 580 Hz), 0,5 s
    chacun ; boucle de 2 s. Timbre de trompe : carré adouci, un peu nasal."""
    # 2,05 s rendues, dont 0,05 fondues sur le début : boucle de 2 s pile.
    length = 2.05
    t = t_axis(length)
    tone = np.where((t % 1.0) < 0.5, 435.0, 580.0)
    # Glissement bref entre les deux tons, comme une vraie trompe.
    k = int(SR * 0.02)
    tone = np.convolve(tone, np.ones(k) / k, mode="same")
    phase = 2 * np.pi * np.cumsum(tone) / SR
    x = np.tanh(3.0 * np.sin(phase)) + 0.25 * np.sin(2 * phase + 0.4)
    x = fft_filter(x, 300, 3500)
    return seamless(np.stack([x, x], axis=1), 0.05)


def dawn():
    """Aube (scènes de fin) : 26 s sans boucle. Une nappe qui s'ouvre lentement
    (D maj7, B m9, G maj7, A sus4 puis A), des cloches douces qui égrènent
    l'accord, une basse ronde ; tout s'éteint sur la dernière note."""
    length = 26.0
    n = int(SR * length)
    track = np.zeros((n, 2))
    prog = [[50, 57, 61, 64, 66], [47, 54, 57, 61, 62], [43, 50, 54, 57, 59], [45, 52, 57, 62, 64]]
    seg = 6.0
    for k, chord in enumerate(prog):
        t0 = k * seg
        dur = seg + (2.5 if k < 3 else 2.0)
        m = int(SR * dur)
        tt = np.arange(m) / SR
        pad = np.zeros(m)
        for note in chord[1:]:
            for det in (-0.003, 0.0, 0.003):
                pad += saw(note_freq(note) * (1 + det), tt, 8) * 0.18
        # Filtre qui s'ouvre au fil du morceau : l'aube qui monte.
        pad = fft_filter(pad, 80, 700 + 900 * k)
        e = np.minimum(1.0, tt / 2.2) * np.minimum(1.0, (dur - tt) / 2.5)
        place(track, pad * e, t0, 0.55)
        # Basse à l'octave du haut-parleur d'un téléphone (sous 80 Hz, il ne joue rien).
        bass = np.sin(2 * np.pi * note_freq(chord[0]) * tt) * e * 0.35
        place(track, bass, t0, 0.8)
        # Cloches : l'accord égrené, de plus en plus présent.
        if k >= 1:
            for j, note in enumerate(chord[2:] + [chord[1] + 12]):
                bt = t_axis(3.0)
                bell = (np.sin(2 * np.pi * note_freq(note + 12) * bt)
                        + 0.3 * np.sin(2 * np.pi * note_freq(note + 24) * 2.01 * bt)) * np.exp(-bt / 0.9)
                place(track, bell, t0 + 0.4 + j * 0.75, 0.10 + 0.04 * k, pan=0.5 * np.sin(j * 1.7))
    # Résolution : A sus4 glisse vers A (le Do# arrive à 21 s).
    tt = t_axis(5.0)
    e = np.minimum(1.0, tt / 1.5) * np.exp(-np.maximum(tt - 1.5, 0) / 1.4)
    res = sum(saw(note_freq(nn), tt, 8) for nn in (57, 61, 64, 69)) * 0.12
    place(track, fft_filter(res, 80, 3000) * e, 21.0, 0.6)
    fade = np.minimum(1.0, (length - np.arange(n) / SR) / 3.0)[:, None]
    return reverb(track * fade, 2.6, 0.35)


# --- Radios années 80-90 ---------------------------------------------------------
# Trois stations de plus, chacune avec sa signature d'époque : basse en octaves
# et cloches FM (italo disco), piano house et supersaw (eurodance), piano
# électrique FM et caisse claire à réverbération coupée (ballade). Leur propre
# générateur aléatoire : les autres sons restent identiques.

r80 = np.random.default_rng(1986)


def fm(freq, t, ratio, index, decay_index=0.6):
    """Synthèse FM à deux opérateurs (façon DX7) : l'indice décroît, le son s'adoucit."""
    idx = index * np.exp(-t / decay_index)
    return np.sin(2 * np.pi * freq * t + idx * np.sin(2 * np.pi * freq * ratio * t))


def chorus(x, depth=0.0025, rate=0.6, mix=0.5):
    """Chorus : copie retardée dont le retard ondule (épaissit les nappes)."""
    n = len(x)
    t = np.arange(n) / SR
    d = (0.008 + depth * (1 + np.sin(2 * np.pi * rate * t))) * SR
    idx = np.clip(np.arange(n) - d, 0, n - 1)
    lo = np.floor(idx).astype(int)
    fr = idx - lo
    hi = np.minimum(lo + 1, n - 1)
    return x * (1 - mix) + (x[lo] * (1 - fr) + x[hi] * fr) * mix


def linn_kick(gain=1.0):
    t = t_axis(0.35)
    f = 50 + 110 * np.exp(-t / 0.025)
    click = r80.normal(0, 1, len(t)) * np.exp(-t / 0.003) * 0.3
    return (np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.16) + click) * gain


def gated_snare(gain=1.0, gate=0.32):
    """Caisse claire des années 80 : grosse réverbération coupée net."""
    t = t_axis(0.6)
    body = np.sin(2 * np.pi * 185 * t) * np.exp(-t / 0.06)
    noise = fft_filter(r80.normal(0, 1, len(t)), 900, 8000) * np.exp(-t / 0.12)
    hitn = body * 0.7 + noise
    wet = reverb(np.stack([hitn, hitn], 1), 1.2, 0.9, seed=8)[:, 0]
    g = (t < gate).astype(float) * np.clip((gate - t) / 0.02, 0, 1)
    return (hitn * 0.6 + wet * 1.4 * g) * gain


def clap(gain=1.0):
    t = t_axis(0.25)
    n = fft_filter(r80.normal(0, 1, len(t)), 1000, 6000)
    e = np.zeros_like(t)
    for k, d in enumerate((0.0, 0.011, 0.022)):
        e += (t >= d) * np.exp(-np.maximum(t - d, 0) / (0.006 if k < 2 else 0.09))
    return n * e * gain


def hat909(open_=False, gain=1.0):
    t = t_axis(0.3 if open_ else 0.06)
    n = fft_filter(r80.normal(0, 1, len(t)), 7000, None)
    return n * np.exp(-t / (0.09 if open_ else 0.014)) * gain


def poly_pad(notes, dur, cutoff=2400, attack=0.4):
    """Nappe polyphonique : scies désaccordées, filtre doux, chorus."""
    n = int(SR * dur)
    tt = np.arange(n) / SR
    x = np.zeros(n)
    for m in notes:
        for det in (-0.005, 0.0, 0.005):
            x += saw(note_freq(m) * (1 + det), tt, 10)
    x = fft_filter(x, 150, cutoff) * env(n, attack, dur, 0.85, min(0.6, dur * 0.3))
    return chorus(x / max(1, len(notes)))


def italo():
    """Italo disco, 118 bpm : basse en octaves, boîte à rythmes, cloches FM,
    nappes, mélodie carrée avec vibrato. Am F C G."""
    bpm = 118
    beat = 60 / bpm
    bars = 32
    track = np.zeros((int(SR * bars * 4 * beat), 2))
    prog = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]
    melody = [69, 72, 76, 74, 72, 71, 72, 69, 67, 69, 71, 72, 74, 72, 71, 67]
    for bar in range(bars):
        chord = prog[(bar // 2) % 4]
        t0 = bar * 4 * beat
        intro = bar < 4
        # Basse en octaves, doubles croches : LE son italo.
        for i in range(16):
            m = chord[0] - 24 + (12 if i % 2 else 0)
            n = int(SR * beat * 0.22)
            tt = np.arange(n) / SR
            b = fft_filter(saw(note_freq(m), tt, 16), None, 1100 + 500 * (i % 2)) * env(n, 0.002, 0.07, 0.2, 0.01)
            place(track, b, t0 + i * beat / 4, 0.3 if not intro else 0.18)
        if bar % 2 == 0:
            pad = poly_pad([m + 12 for m in chord], 8 * beat, 2600)
            place(track, pad, t0, 0.07, -0.4)
            place(track, pad, t0 + 0.015, 0.07, 0.4)
        if not intro:
            for i in range(4):
                place(track, linn_kick(), t0 + i * beat, 0.6)
                if i in (1, 3):
                    place(track, clap(), t0 + i * beat, 0.3, 0.1)
                    place(track, gated_snare(gate=0.22), t0 + i * beat, 0.18)
            for i in range(8):
                place(track, hat909(open_=(i % 2 == 1)), t0 + i * beat / 2, 0.06 if i % 2 else 0.05, 0.3)
        # Cloches FM en arpège.
        for i in range(8):
            m = chord[i % 3] + 24
            tt = t_axis(0.6)
            bell = fm(note_freq(m), tt, 3.5, 2.5, 0.25) * np.exp(-tt / 0.3)
            place(track, bell, t0 + i * beat / 2 + beat / 4, 0.04, 0.6 if i % 2 else -0.6)
        # Mélodie (après l'intro, et pas pendant la pause).
        if 8 <= bar < 24 or bar >= 28:
            for i in range(2):
                m = melody[(bar * 2 + i) % len(melody)]
                n = int(SR * beat * 1.8)
                tt = np.arange(n) / SR
                vib = 1 + 0.006 * np.sin(2 * np.pi * 6.0 * tt) * np.clip(tt / 0.25, 0, 1)
                lead = square(note_freq(m), tt * vib, 11) * env(n, 0.01, 1.0, 0.6, 0.15)
                lead = fft_filter(lead, None, 3800)
                place(track, lead, t0 + i * 2 * beat, 0.07, -0.1)
                place(track, lead, t0 + i * 2 * beat + beat * 0.75, 0.03, 0.5)
    return reverb(track, 1.6, 0.25)


def eurodance():
    """Eurodance 90, 130 bpm : kick à chaque temps, basse à contretemps,
    accords de piano house (FM), supersaw, charleston ouvert à contretemps."""
    bpm = 130
    beat = 60 / bpm
    bars = 32
    track = np.zeros((int(SR * bars * 4 * beat), 2))
    prog = [[50, 53, 57], [46, 50, 53], [48, 52, 55], [45, 49, 52]]   # Dm Bb C A
    riff = [0, 0, 2, 0, 1, 0, 2, 1]
    for bar in range(bars):
        chord = prog[bar % 4]
        t0 = bar * 4 * beat
        build = bar < 4
        for i in range(4):
            place(track, linn_kick(), t0 + i * beat, 0.42)
            if not build:
                place(track, hat909(open_=True), t0 + i * beat + beat / 2, 0.09, 0.25)
                if i in (1, 3):
                    place(track, clap(), t0 + i * beat, 0.25)
            # Basse à contretemps.
            n = int(SR * beat * 0.4)
            tt = np.arange(n) / SR
            b = fft_filter(saw(note_freq(chord[0] - 12), tt, 14), None, 700) * env(n, 0.003, 0.15, 0.3, 0.03)
            place(track, b, t0 + i * beat + beat / 2, 0.2)
        # Piano house : accords plaqués, syncopés.
        if not build:
            for k, pos in enumerate((0.0, 0.75, 1.5, 2.5, 3.25)):
                tt = t_axis(0.5)
                x = sum(fm(note_freq(m + 12), tt, 1.0, 1.8, 0.12) + 0.4 * fm(note_freq(m + 24), tt, 2.0, 1.0, 0.08)
                        for m in chord) * np.exp(-tt / 0.22)
                place(track, fft_filter(x, 200, 6000), t0 + pos * beat, 0.16, -0.2 + 0.1 * k)
        # Supersaw en riff, sections principales.
        if 8 <= bar < 24 or bar >= 28:
            for i in range(8):
                m = chord[riff[i]] + 24
                n = int(SR * beat * 0.45)
                tt = np.arange(n) / SR
                x = sum(saw(note_freq(m) * (1 + d), tt, 12) for d in (-0.012, -0.006, 0.0, 0.006, 0.012))
                x = fft_filter(x, 300, 5000) * env(n, 0.005, 0.25, 0.3, 0.05)
                place(track, chorus(x), t0 + i * beat / 2, 0.07, 0.4 if i % 2 else -0.4)
    return reverb(track, 1.2, 0.18)


def ballad():
    """Power ballad 86, 84 bpm : piano électrique FM (DX7), basse ronde,
    cordes, caisse claire énorme à réverbération coupée. C G Am F."""
    bpm = 84
    beat = 60 / bpm
    bars = 16
    track = np.zeros((int(SR * bars * 4 * beat), 2))
    prog = [[48, 52, 55, 60], [43, 50, 55, 59], [45, 52, 57, 60], [41, 48, 53, 57]]
    melody = [76, 74, 72, 74, 76, 79, 77, 76, 74, 72, 71, 72, 74, 72, 69, 67]
    for bar in range(bars):
        chord = prog[bar % 4]
        t0 = bar * 4 * beat
        # Piano électrique FM : accord, puis notes égrenées.
        for k, (pos, notes) in enumerate(((0.0, chord[1:]), (1.5, chord[2:]), (2.0, chord[1:3]), (3.0, chord[2:]))):
            tt = t_axis(2.2)
            x = sum(fm(note_freq(m + 12), tt, 1.0, 2.2, 0.5) + 0.25 * fm(note_freq(m + 12), tt, 14.0, 0.6, 0.05)
                    for m in notes) * np.exp(-tt / 0.9)
            place(track, x, t0 + pos * beat, 0.05, -0.3 + 0.2 * k)
        # Basse ronde.
        n = int(SR * beat * 3.8)
        tt = np.arange(n) / SR
        b = (np.sin(2 * np.pi * note_freq(chord[0] - 12) * tt) + 0.3 * np.sin(4 * np.pi * note_freq(chord[0] - 12) * tt)) \
            * env(n, 0.01, 2.0, 0.6, 0.3)
        place(track, b, t0, 0.28)
        # Cordes à partir de la 5e mesure.
        if bar >= 4:
            place(track, poly_pad([m + 12 for m in chord], 4 * beat, 1800, 0.8), t0, 0.06, 0.3)
        # Batterie : la caisse claire énorme sur 2 et 4.
        if bar >= 2:
            for i in range(4):
                if i in (0, 2):
                    place(track, linn_kick(), t0 + i * beat, 0.55)
                else:
                    place(track, gated_snare(gate=0.4), t0 + i * beat, 0.32)
            for i in range(8):
                place(track, hat909(), t0 + i * beat / 2, 0.035, 0.3)
        # Mélodie « guitare chantée » : sinus et scie douce, vibrato lent.
        if bar >= 4:
            for i in range(2):
                m = melody[(bar * 2 + i) % len(melody)]
                n = int(SR * beat * 1.9)
                tt = np.arange(n) / SR
                vib = 1 + 0.008 * np.sin(2 * np.pi * 5.0 * tt) * np.clip(tt / 0.4, 0, 1)
                lead = (np.sin(2 * np.pi * note_freq(m) * tt * vib) + 0.35 * saw(note_freq(m), tt * vib, 6)) \
                    * env(n, 0.04, 1.5, 0.7, 0.2)
                place(track, fft_filter(lead, None, 3000), t0 + i * 2 * beat, 0.08, 0.15)
    return reverb(track, 2.4, 0.32)


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
    save("dawn", dawn())
    save("siren", siren(), loop=True)
    save("music_italo", italo(), loop=True)
    save("music_euro", eurodance(), loop=True)
    save("music_ballad", ballad(), loop=True)


if __name__ == "__main__":
    main()
