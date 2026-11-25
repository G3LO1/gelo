#!/usr/bin/env python3
"""Writes flipbook fixtures for tests/roblox-animation-vfx/run.sh into <out-dir>:

  frames/        the committed slash_4x4.png cut back into 16 frames (pack round trip)
  big/           16 frames of 300x300 whose shape fills the frame (pack --fit must add the margin)
  colored.gif    an animated GIF in orange on black (pack --white must make a white mask)
  edge.png       4x4 sheet, frame 6 painted up to the right edge
  near.png       4x4 sheet, frame 2 painted 2 px from the top edge
  empty.png      4x4 sheet, frame 16 empty
  haze.png       4x4 sheet, frame 3 a faint grey haze around the shape
  tinted.png     4x4 sheet drawn in blue instead of white
  oblong.png     512x256 sheet; npot.png 480x480 sheet; huge.png 2048x2048 sheet
  many/          20 frames (too many for 4x4)

Usage: make_flipbooks.py <committed slash_4x4.png> <out-dir>
"""

import os
import sys

from PIL import Image, ImageDraw


def disc(size, color=(255, 255, 255), inset=24):
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    ImageDraw.Draw(img).ellipse([inset, inset, size - inset, size - inset], fill=color + (255,))
    return img


def sheet(cell=128, grid=4, frame=None, color=(255, 255, 255)):
    out = Image.new("RGBA", (cell * grid, cell * grid), (255, 255, 255, 0))
    for i in range(grid * grid):
        out.paste(frame(i) if frame else disc(cell, color), ((i % grid) * cell, (i // grid) * cell))
    return out


def main():
    slash, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    source = Image.open(slash).convert("RGBA")
    cell = source.width // 4
    for folder in ("frames", "big", "many"):
        os.makedirs(os.path.join(out, folder), exist_ok=True)
    for i in range(16):
        x, y = (i % 4) * cell, (i // 4) * cell
        source.crop((x, y, x + cell, y + cell)).save(os.path.join(out, "frames", f"{i + 1:02d}.png"))
        big = Image.new("RGBA", (300, 300), (255, 255, 255, 0))
        ImageDraw.Draw(big).ellipse([10 + i, 0, 300 - 10 - i, 300], fill=(255, 255, 255, 255))  # touches top/bottom
        big.save(os.path.join(out, "big", f"{i + 1:02d}.png"))
    for i in range(20):
        disc(64, inset=12).save(os.path.join(out, "many", f"{i + 1:02d}.png"))

    gif = []
    for i in range(16):
        frame = Image.new("RGB", (128, 128), (0, 0, 0))
        ImageDraw.Draw(frame).ellipse([20 + i, 30, 100 - i // 2, 98], fill=(255, 140, 20))
        gif.append(frame)
    gif[0].save(os.path.join(out, "colored.gif"), save_all=True, append_images=gif[1:], duration=60, loop=0)

    def edge(i):
        img = disc(128)
        if i == 5:
            ImageDraw.Draw(img).rectangle([100, 50, 127, 70], fill=(255, 255, 255, 255))
        return img

    def near(i):
        img = disc(128)
        if i == 1:
            ImageDraw.Draw(img).rectangle([50, 2, 70, 30], fill=(255, 255, 255, 255))
        return img

    def empty(i):
        return Image.new("RGBA", (128, 128), (255, 255, 255, 0)) if i == 15 else disc(128)

    def haze(i):
        img = disc(128, inset=44)
        if i == 2:
            fog = Image.new("RGBA", (128, 128), (255, 255, 255, 0))
            ImageDraw.Draw(fog).rectangle([6, 6, 121, 121], fill=(200, 200, 200, 24))
            fog.alpha_composite(img)
            return fog
        return img

    sheet(frame=edge).save(os.path.join(out, "edge.png"))
    sheet(frame=near).save(os.path.join(out, "near.png"))
    sheet(frame=empty).save(os.path.join(out, "empty.png"))
    sheet(frame=haze).save(os.path.join(out, "haze.png"))
    sheet(color=(60, 120, 255)).save(os.path.join(out, "tinted.png"))
    Image.new("RGBA", (512, 256), (255, 255, 255, 0)).save(os.path.join(out, "oblong.png"))
    sheet(cell=120).save(os.path.join(out, "npot.png"))
    sheet(cell=512).save(os.path.join(out, "huge.png"))


if __name__ == "__main__":
    main()
