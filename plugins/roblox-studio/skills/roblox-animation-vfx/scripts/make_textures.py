#!/usr/bin/env python3
"""Generates the particle textures Vfx.luau expects: white shapes on transparent background
(tinted in game by ParticleEmitter.Color), 128x128 PNG. They are original, so they can be
uploaded and used anywhere.

Usage: make_textures.py [out-dir] [--size 128]
Writes glow.png, star.png, spark.png, smoke.png, ring.png.
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


TEXTURES = {"glow": glow, "star": star, "spark": spark, "smoke": smoke, "ring": ring}


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
