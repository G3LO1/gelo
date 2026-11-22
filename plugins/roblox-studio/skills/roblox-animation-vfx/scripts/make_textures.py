#!/usr/bin/env python3
"""Generates the particle textures Vfx.luau expects: white shapes on transparent background
(tinted in game by ParticleEmitter.Color), 128x128 PNG. They are original, so they can be
uploaded and used anywhere.

Usage: make_textures.py [out-dir] [--size 128]
Writes glow.png, star.png, spark.png, smoke.png, ring.png and slash_4x4.png, a 4x4 flipbook
sheet (16 frames of --size px: a sword slash that grows in, holds and tears apart along its
flow, tapered to a point at both ends, 4+ px clear of every cell edge) for Vfx's Slash preset.
"""

import argparse
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.dont_write_bytecode = True  # importing flipbook.py must not leave __pycache__ in the skill folder
from flipbook import pack  # noqa: E402


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


def slash_frames(size):
    """16 white frames of a slash arc. s runs tail (0) -> head (1); the head leads the swing."""
    ss = 4  # supersampling
    big = size * ss
    cx, cy, radius = 0.5 * big, 0.78 * big, 0.40 * big
    start, sweep = math.radians(160), math.radians(-140)  # over the top, left -> right
    max_width = 0.15 * big

    def profile(s):
        # thick head, long thin tail, both ends a point
        return (s**1.8) * ((1 - s) ** 0.75) / ((1.8 / 2.55) ** 1.8 * (0.75 / 2.55) ** 0.75)

    def point(theta, r):
        return (cx + r * math.cos(theta), cy - r * math.sin(theta))

    frames = []
    for i in range(16):
        if i < 5:  # grow in
            t = (i + 1) / 5
            head = t * t * (3 - 2 * t)
            tail, width, fade, tears = 0.0, 0.6 + 0.4 * head, 1.0, 0
        elif i < 9:  # live: the tail catches up a little, the body swells and settles
            head, tail, width, fade, tears = 1.0, 0.03 * (i - 5), (1.06, 1.1, 1.06, 1.0)[i - 5], 1.0, 0
        else:  # break apart
            k = (i - 8) / 7
            head, tail, width, fade, tears = 1.0, 0.7 * k, 1 - 0.55 * k, 1 - 0.7 * k, 1 + round(4 * k)
        mask = Image.new("L", (big, big), 0)
        draw = ImageDraw.Draw(mask)
        steps = 64
        outer, inner = [], []
        for n in range(steps + 1):
            s = n / steps
            theta = start + sweep * (tail + (head - tail) * s)
            half = 0.5 * max_width * width * profile(s)
            outer.append(point(theta, radius + half))
            inner.append(point(theta, radius - half * 0.6))  # sharper inner edge
        draw.polygon(outer + inner[::-1], fill=255)
        # rips along the flow: one fast streak always, more as it tears apart
        rng = random.Random(7 + i)
        for n in range(1 + tears):
            offset = rng.uniform(-0.25, 0.3) * max_width * width
            a, b = sorted((rng.uniform(tail + 0.05, head - 0.1), rng.uniform(tail + 0.2, head)))
            line = [point(start + sweep * (a + (b - a) * m / 24), radius + offset) for m in range(25)]
            draw.line(line, fill=0, width=max(1, round((1.2 + 0.8 * (n > 0)) * ss)))
        frame = mask.resize((size, size), Image.LANCZOS).filter(ImageFilter.GaussianBlur(size / 160))
        frame = frame.point(lambda v: int(v * fade))
        img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
        img.putalpha(frame)
        frames.append(img)
    return frames


def slash_sheet(size):
    sheet, _ = pack(slash_frames(size), grid=4, cell=size)
    return sheet


TEXTURES = {"glow": glow, "star": star, "spark": spark, "smoke": smoke, "ring": ring}
FLIPBOOKS = {"slash_4x4": slash_sheet}  # size = one frame; the sheet is 4x bigger


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", nargs="?", default="textures")
    ap.add_argument("--size", type=int, default=128)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for name, make in {**TEXTURES, **FLIPBOOKS}.items():
        path = os.path.join(args.out, f"{name}.png")
        make(args.size).save(path, optimize=True)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
