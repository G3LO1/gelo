#!/usr/bin/env python3
"""Generates the layer images used by assets/examples/components.json: white shapes on a
transparent background (ImageColor3 tints each layer in game), cut for 9-slice. They are
original, so they can be uploaded and used anywhere.

Usage: make_ui_images.py [out-dir]
Writes (size, SliceCenter for the spec):
  panel.png  96x96   filled rounded rectangle, radius 24     SliceCenter [28, 28, 68, 68]
  edge.png   96x96   3 px rounded outline (edge light)       SliceCenter [28, 28, 68, 68]
  glow.png   128x128 soft glow ring, empty middle            SliceCenter [56, 56, 72, 72]
  radial.png 128x128 round soft light behind an item         (not sliced)
  gem.png    128x128 a colored, faceted gem item icon        (not sliced)
Corners stay whole when the element stretches; only the flat middle band is repeated, so one
image fits every card and button size.
"""

import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 4  # supersampling for smooth edges

SLICES = {"panel": (28, 28, 68, 68), "edge": (28, 28, 68, 68), "glow": (56, 56, 72, 72)}


def white(alpha):
    img = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    img.putalpha(alpha)
    return img


def rounded(size, inset, radius, width=None):
    big = Image.new("L", (size * SS, size * SS), 0)
    box = [inset * SS, inset * SS, (size - inset) * SS - 1, (size - inset) * SS - 1]
    draw = ImageDraw.Draw(big)
    if width:
        draw.rounded_rectangle(box, radius * SS, outline=255, width=width * SS)
    else:
        draw.rounded_rectangle(box, radius * SS, fill=255)
    return big.resize((size, size), Image.LANCZOS)


def panel():
    return white(rounded(96, 0, 24))


def edge():
    return white(rounded(96, 1, 23, width=3))


def glow():
    # the light sits outside a rounded rectangle 40 px in from the edges and fades out before
    # the image edge, so the sliced corners never show a hard border
    # and leaves the middle empty: the card's see-through glass must not show a bright blob
    core = Image.new("L", (128, 128), 0)
    ImageDraw.Draw(core).rounded_rectangle([40, 40, 87, 87], 20, fill=255)
    soft = core.filter(ImageFilter.GaussianBlur(10)).point(lambda v: min(255, int(v * 1.25)))
    hole = Image.new("L", (128, 128), 0)
    ImageDraw.Draw(hole).rounded_rectangle([50, 50, 77, 77], 10, fill=255)
    hole = hole.filter(ImageFilter.GaussianBlur(2))
    return white(ImageChops.multiply(soft, ImageChops.invert(hole)))


def radial():
    size = 128
    img = Image.new("L", (size, size), 0)
    px = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            r = (((x - c) ** 2 + (y - c) ** 2) ** 0.5) / c
            px[x, y] = int(255 * max(0.0, 1 - r) ** 2.2)
    return white(img)


def gem():
    size = 128
    big = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(big)

    def p(x, y):
        return (x * SS, y * SS)

    top, crown_l, crown_r, mid_l, mid_r, tip = p(64, 18), p(34, 30), p(94, 30), p(20, 50), p(108, 50), p(64, 112)
    facets = [
        ([crown_l, top, p(64, 50), mid_l], (120, 225, 255, 255)),
        ([top, crown_r, mid_r, p(64, 50)], (70, 175, 245, 255)),
        ([mid_l, p(64, 50), tip], (45, 135, 225, 255)),
        ([p(64, 50), mid_r, tip], (25, 95, 190, 255)),
    ]
    for points, color in facets:
        draw.polygon(points, fill=color)
    draw.polygon([p(46, 32), p(60, 24), p(56, 40)], fill=(235, 250, 255, 255))  # glint
    return big.resize((size, size), Image.LANCZOS)


IMAGES = {"panel": panel, "edge": edge, "glow": glow, "radial": radial, "gem": gem}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "images"
    os.makedirs(out, exist_ok=True)
    for name, make in IMAGES.items():
        path = os.path.join(out, f"{name}.png")
        make().save(path, optimize=True)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
