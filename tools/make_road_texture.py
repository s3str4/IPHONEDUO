#!/usr/bin/env python3
"""Texture de la chaussée (assets/textures/road.png), 256 × 512, répétable.

Largeur = les 12 m de la chaussée (3 voies) ; hauteur = 12 m de route (le motif
des tirets fait 12 m). RVB : enrobé (grain, gravillons, traces de roues plus
lisses et sombres), lignes de rive continues, deux lignes de voie en tirets
(4,5 m de trait, 7,5 m de vide), peinture un peu usée. Alpha : humidité
(1 = flaque miroir), plus forte dans les ornières et les creux.

    python3 tools/make_road_texture.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

W, H = 256, 512
rng = np.random.default_rng(7)


def periodic_noise(octaves, base, seed):
    """Bruit fractal périodique (se répète sur W × H) par sommes de sinus."""
    r = np.random.default_rng(seed)
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    out = np.zeros((H, W), np.float32)
    amp = 1.0
    for o in range(octaves):
        f = base * 2 ** o
        for _ in range(6):
            kx = r.integers(-f, f + 1)
            ky = r.integers(-f * 2, f * 2 + 1)
            ph = r.uniform(0, 2 * np.pi)
            out += amp * np.sin(2 * np.pi * (kx * x / W + ky * y / H) + ph)
        amp *= 0.55
    out -= out.min()
    return out / out.max()


# Enrobé : gris sombre, grain fin, gravillons clairs.
grain = periodic_noise(5, 3, 1)
asphalt = 0.16 + 0.07 * grain + rng.normal(0.0, 0.025, (H, W))
speckle = rng.random((H, W)) > 0.985
asphalt[speckle] += rng.uniform(0.08, 0.2, speckle.sum())

# Ornières : deux traces par voie, plus lisses (plus sombres) et plus mouillées.
x = np.arange(W) / W * 12.0 - 6.0
ruts = np.zeros(W, np.float32)
for lane in (-4.0, 0.0, 4.0):
    for off in (-0.85, 0.85):
        ruts += np.exp(-((x - lane - off) ** 2) / (2 * 0.28 ** 2))
asphalt -= 0.035 * ruts[None, :]

rgb = np.repeat(asphalt[:, :, None], 3, axis=2)
rgb[:, :, 2] *= 1.04

# Peinture.
paint = np.array([0.88, 0.87, 0.82])
wear = 0.75 + 0.25 * periodic_noise(4, 6, 2)
def line(x0, x1, rows):
    c0, c1 = int((x0 + 6) / 12 * W), int((x1 + 6) / 12 * W)
    for c in range(c0, c1 + 1):
        a = wear[rows, c][:, None]
        rgb[rows, c] = rgb[rows, c] * (1 - a) + paint * a
all_rows = np.arange(H)
line(-5.85, -5.7, all_rows)
line(5.7, 5.85, all_rows)
dash = np.arange(int(H * 4.5 / 12.0))
for lx in (-2.0, 2.0):
    line(lx - 0.08, lx + 0.08, dash)

# Humidité : creux du bruit basse fréquence + ornières.
puddles = periodic_noise(3, 1, 3)
wet = np.clip((puddles - 0.45) * 2.2, 0, 1) * 0.7 + 0.3 * np.clip(ruts[None, :], 0, 1)
wet = np.clip(wet + 0.15, 0, 1)

img = np.dstack([np.clip(rgb, 0, 1), wet])
out = Path(__file__).resolve().parent.parent / "assets/textures/road.png"
Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(out)
print(out)
