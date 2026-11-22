#!/usr/bin/env python3
"""Generates the particle textures Vfx.luau expects: white shapes on transparent background
(tinted in game by ParticleEmitter.Color), 128x128 PNG. They are original, so they can be
uploaded and used anywhere.

Usage: make_textures.py [out-dir] [--size 128]
Writes glow.png, star.png, spark.png, smoke.png, ring.png and burst_4x4.png (a 4x4 flipbook
atlas of size*4 px; check your own atlases with flipbook_check.py).
"""

import argparse
import math
import os
import random

from PIL import Image, ImageFilter


def radial(size, fn):
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    px = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            dx, dy = (x - c) / c, (y - c) / c
            a = max(0.0, min(1.0, fn(dx, dy)))
            px[x, y] = (255, 255, 255, int(a * 255))
    return img


def glow(size):
    return radial(size, lambda dx, dy: math.exp(-((dx * dx + dy * dy) / 0.18)) * (1 if dx * dx + dy * dy < 1 else 0))


def star(size):
    def fn(dx, dy):
        r = math.hypot(dx, dy)
        if r >= 1:
            return 0
        angle = math.atan2(dy, dx)
        arms = abs(math.cos(2 * angle)) ** 8  # 4 sharp arms
        core = math.exp(-(r * r) / 0.02)
        rays = arms * max(0, 1 - r) ** 1.5
        halo = 0.35 * math.exp(-(r * r) / 0.12)
        return core + rays + halo

    return radial(size, fn)


def spark(size):
    # vertical streak: emitters with Squash/speed stretch it further
    return radial(size, lambda dx, dy: math.exp(-(dx * dx) / 0.004) * max(0, 1 - abs(dy)) ** 1.2)


def smoke(size, seed=3):
    rng = random.Random(seed)
    base = Image.new("L", (size, size), 0)
    px = base.load()
    c = (size - 1) / 2
    blobs = [(rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35), rng.uniform(0.25, 0.45)) for _ in range(9)]
    for y in range(size):
        for x in range(size):
            dx, dy = (x - c) / c, (y - c) / c
            v = 0.0
            for bx, by, br in blobs:
                d = ((dx - bx) ** 2 + (dy - by) ** 2) / (br * br)
                v += math.exp(-d * 2.2)
            edge = max(0.0, 1 - math.hypot(dx, dy)) ** 0.6
            px[x, y] = int(min(1.0, v * 0.45) * edge * 255)
    alpha = base.filter(ImageFilter.GaussianBlur(size / 64))
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    img.putalpha(alpha)
    return img


def ring(size):
    return radial(size, lambda dx, dy: math.exp(-((math.hypot(dx, dy) - 0.78) ** 2) / 0.004))


def smoothstep(edge0, edge1, x):
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)


def burst_frame(size, t, waves):
    """One frame of an expanding, hollowing burst (t = 0..1). Stays inside 85% of the
    half-cell, so every frame keeps a transparent margin and never bleeds into its neighbours."""

    def noise(theta, phase):
        return sum(a * math.sin(k * theta + p + phase * w) for k, a, p, w in waves) / 0.9

    def fn(dx, dy):
        r = math.hypot(dx, dy)
        theta = math.atan2(dy, dx)
        grow = 1 - (1 - t) ** 2
        edge = (0.22 + 0.5 * grow) * (1 + 0.18 * max(-1.0, min(1.0, noise(theta, t * 3))))
        if r >= edge:
            return 0.0
        outer = smoothstep(edge, edge - 0.1, r)
        inner_radius = edge * 0.85 * t**1.3
        inner = smoothstep(inner_radius - 0.06, inner_radius + 0.05, r) if t > 0 else 1.0
        # tongues break apart in the second half
        breakup = max(0.0, min(1.0, 0.55 + 0.45 * noise(theta * 1.5 + r * 6, 5 + t * 4) + (1 - t) * 1.2))
        fade = 1 - 0.8 * max(0.0, (t - 0.4) / 0.6) ** 1.3
        return outer * inner * breakup * fade

    return radial(size, fn)


def burst_4x4(size, seed=7):
    """Layered flipbook atlas: 16 white mask frames in a 4x4 grid (frame size = --size, so
    128 px frames give a 512 px sheet). Vfx.luau tints each layer per colour variant."""
    rng = random.Random(seed)
    waves = [(k, rng.uniform(0.15, 0.3), rng.uniform(0, math.tau), rng.uniform(-1, 1)) for k in (3, 5, 7, 11)]
    atlas = Image.new("RGBA", (size * 4, size * 4), (255, 255, 255, 0))
    for index in range(16):
        frame = burst_frame(size, index / 15, waves)
        atlas.paste(frame, ((index % 4) * size, (index // 4) * size))
    return atlas


TEXTURES = {"glow": glow, "star": star, "spark": spark, "smoke": smoke, "ring": ring, "burst_4x4": burst_4x4}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", nargs="?", default="textures")
    ap.add_argument("--size", type=int, default=128)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for name, make in TEXTURES.items():
        path = os.path.join(args.out, f"{name}.png")
        make(args.size).save(path, optimize=True)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
