#!/usr/bin/env python3
"""Checks a flipbook atlas before it is uploaded for a ParticleEmitter (FlipbookLayout).

Errors (exit 1):
  - the sheet is not an exact multiple of the grid (Roblox shows FlipbookIncompatible),
  - no alpha channel (white masks need it to be tinted per layer),
  - a frame reaches its cell edge: pixels inside the transparent margin bleed into the
    neighbouring frame once the texture is mip-filtered on phones,
  - an empty frame (the animation blinks).
Warnings: not square, not a power of two, over 1024 px (memory; clients drop flipbooks when
low on memory), a grid Roblox only supports as Custom, coloured masks (tint per layer works
best on white).

Usage: flipbook_check.py atlas.png [--grid 4 | --grid 8x4] [--margin PX] [--threshold 8]
                         [--preview preview.png]
The preview puts the sheet on a dark checkerboard with the cell grid, the margin band and
the failing frames outlined in red, numbered in playback order.
"""

from __future__ import annotations

import argparse
import sys

from PIL import Image, ImageDraw, ImageStat

STANDARD = {(2, 2): "Grid2x2", (4, 4): "Grid4x4", (8, 8): "Grid8x8"}


def parse_grid(text: str) -> tuple[int, int]:
    cols, _, rows = text.lower().partition("x")
    return int(cols), int(rows or cols)


def check(path: str, grid: tuple[int, int], margin: int | None, threshold: int):
    errors, warnings, frames = [], [], []
    try:
        img = Image.open(path)
        img.load()
    except Exception as exc:  # noqa: BLE001 - report any unreadable file the same way
        return [f"cannot open {path}: {exc}"], warnings, frames, None, None
    cols, rows = grid
    width, height = img.size
    if width % cols or height % rows:
        errors.append(f"{width}x{height} is not an exact multiple of the {cols}x{rows} grid (Roblox: FlipbookIncompatible)")
        return errors, warnings, frames, img, None
    if "A" not in img.getbands():
        errors.append(f"mode {img.mode} has no alpha channel: export white masks on a transparent background")
        return errors, warnings, frames, img, None
    if width != height:
        warnings.append(f"{width}x{height} is not square: frames will be stretched unless the art is drawn for it")
    for side in (width, height):
        if side & (side - 1):
            warnings.append(f"{side} px is not a power of two: mip-mapping and compression work best on 2^n sheets")
            break
    if max(width, height) > 1024:
        warnings.append(f"{max(width, height)} px is over 1024: flipbooks cost memory, keep hero sheets at 1024 or below")
    if (cols, rows) not in STANDARD:
        warnings.append(f"{cols}x{rows} needs FlipbookLayout Custom with FlipbookSizeX={cols}, FlipbookSizeY={rows}")

    rgba = img.convert("RGBA")
    cell_w, cell_h = width // cols, height // rows
    pad = margin if margin is not None else max(2, min(cell_w, cell_h) // 32)
    alpha = rgba.getchannel("A")
    colour_sum = [0.0, 0.0, 0.0]
    colour_count = 0
    for index in range(cols * rows):
        x0, y0 = (index % cols) * cell_w, (index // cols) * cell_h
        cell = alpha.crop((x0, y0, x0 + cell_w, y0 + cell_h))
        peak = cell.getextrema()[1]
        coverage = sum(cell.histogram()[threshold + 1 :]) / (cell_w * cell_h)
        touched = []
        bands = {
            "top": (0, 0, cell_w, pad),
            "bottom": (0, cell_h - pad, cell_w, cell_h),
            "left": (0, 0, pad, cell_h),
            "right": (cell_w - pad, 0, cell_w, cell_h),
        }
        for side, box in bands.items():
            if cell.crop(box).getextrema()[1] > threshold:
                touched.append(side)
        if touched:
            errors.append(f"frame {index} (row {index // cols + 1}, col {index % cols + 1}) reaches the {'/'.join(touched)} edge inside the {pad} px margin")
        if peak <= max(threshold, 16):
            errors.append(f"frame {index} is empty (max alpha {peak})")
        frames.append({"index": index, "coverage": coverage, "touched": touched, "empty": peak <= max(threshold, 16)})
        # average colour of the visible pixels, to spot coloured masks
        mask = cell.point(lambda a: 255 if a > 32 else 0)
        count = sum(mask.histogram()[255:])
        if count:
            stat = ImageStat.Stat(rgba.crop((x0, y0, x0 + cell_w, y0 + cell_h)).convert("RGB"), mask)
            for channel in range(3):
                colour_sum[channel] += stat.mean[channel] * count
            colour_count += count
    if colour_count:
        r, g, b = (c / colour_count for c in colour_sum)
        if max(r, g, b) - min(r, g, b) > 40 or min(r, g, b) < 200:
            warnings.append(f"masks are not white (average RGB {r:.0f},{g:.0f},{b:.0f}): ParticleEmitter.Color multiplies, so per-layer tints lose range")
    return errors, warnings, frames, img, (cell_w, cell_h, pad)


def preview(img: Image.Image, grid, cells, frames, out: str):
    cols, rows = grid
    cell_w, cell_h, pad = cells
    width, height = img.size
    board = Image.new("RGBA", (width, height), (30, 32, 38, 255))
    draw = ImageDraw.Draw(board)
    step = max(4, cell_w // 8)
    for y in range(0, height, step):
        for x in range(0, width, step):
            if (x // step + y // step) % 2:
                draw.rectangle((x, y, x + step - 1, y + step - 1), fill=(40, 43, 50, 255))
    board.alpha_composite(img.convert("RGBA"))
    draw = ImageDraw.Draw(board)
    for frame in frames:
        index = frame["index"]
        x0, y0 = (index % cols) * cell_w, (index // cols) * cell_h
        bad = frame["touched"] or frame["empty"]
        draw.rectangle((x0 + pad, y0 + pad, x0 + cell_w - 1 - pad, y0 + cell_h - 1 - pad), outline=(90, 160, 255, 160))
        draw.rectangle((x0, y0, x0 + cell_w - 1, y0 + cell_h - 1), outline=(255, 60, 60, 255) if bad else (120, 120, 130, 255), width=3 if bad else 1)
        draw.text((x0 + pad + 2, y0 + pad + 1), str(index), fill=(255, 220, 90, 255))
    board.convert("RGB").save(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("atlas")
    ap.add_argument("--grid", default="4", help="columns x rows, e.g. 4 or 8x4 (default 4)")
    ap.add_argument("--margin", type=int, help="transparent band per cell edge in px (default cell/32, at least 2)")
    ap.add_argument("--threshold", type=int, default=8, help="alpha above this counts as visible (default 8)")
    ap.add_argument("--preview", help="write a PNG contact sheet with the grid and failing frames")
    args = ap.parse_args()
    grid = parse_grid(args.grid)
    errors, warnings, frames, img, cells = check(args.atlas, grid, args.margin, args.threshold)
    if img is not None and cells:
        cell_w, cell_h, pad = cells
        layout = STANDARD.get(grid, f"Custom {grid[0]}x{grid[1]}")
        print(f"{args.atlas}: {img.size[0]}x{img.size[1]}, {layout}, {len(frames)} frames of {cell_w}x{cell_h} px, margin {pad} px")
        print("coverage per frame: " + " ".join(f"{f['coverage'] * 100:.0f}%" for f in frames))
        if args.preview:
            preview(img, grid, cells, frames, args.preview)
            print(f"wrote {args.preview}")
    for message in errors:
        print(f"error: {message}")
    for message in warnings:
        print(f"warning: {message}")
    print(f"{'FAILED' if errors else 'OK'}: {len(errors)} error(s), {len(warnings)} warning(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
