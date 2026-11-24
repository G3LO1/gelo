#!/usr/bin/env python3
"""Packs rendered effect frames into Roblox ParticleEmitter flipbook sheets.

Effects are see-through and a renderer can't film see-through, so render every frame twice,
once on a pure black background and once on a pure white one. For a pixel with colour C and
opacity a, the black render is a*C and the white render is a*C + (1 - a), so
    alpha = 1 - (white - black)        colour = black / alpha
which gives a clean cut-out on any background (soft glows and dark smoke included).

Usage:
  pack_flipbook.py --black frames_black/ --white frames_white/ -o out/ --name Blast [options]
  pack_flipbook.py --rgba frames_rgba/ -o out/ --name Blast [options]     # frames already have alpha

Frames are read in file-name order (PNG/JPG/WEBP/TGA/BMP), the black and white folders must
match frame for frame. Output: out/<name>_1.png ... out/<name>_N.png (square sheets, power of
two, up to 1024 px, grid x grid frames each, row by row from the top-left) and
out/<name>.flipbook.json with the values to put on the ParticleEmitters.

Options:
  --grid 4            frames per row/column: 2, 4 or 8 (4 -> 16 frames per sheet, the default)
  --sheet-size 1024   sheet edge in px (power of two, <= 1024); frame edge = sheet / grid
  --frames N          resample to N evenly spaced frames (default: use every frame)
  --skip-first K      drop the first K frames (one-shots usually start at frame 2: the first
                      frame is the simulation warm-up)
  --loop-blend K      cross-fade the last K frames into the first K so a loop has no jump
  --fps 24            playback rate; Roblox plays flipbooks at 20-30 frames per second
  --fit pad|crop      non-square renders: letterbox (default) or centre-crop to a square
  --color keep|white  keep the effect colours, or output white shapes so ParticleEmitter.Color
                      tints them (a single sheet then serves every colour)
  --tolerance 6       matte sanity check, in 0-255 steps (see below)

Sanity check: in a perfect black/white pair the colour in the black render can never be
brighter than the opacity. Pixels that break that mean the two renders don't differ only by the
background (colour management, bloom, or world lighting that changes with the background), and
the script warns with the share of bad pixels. Exit code 1 on errors, 0 otherwise.
Needs: python3 + pillow.
"""

import argparse
import json
import math
import os
import sys

from PIL import Image, ImageChops

IMAGE_EXTENSIONS = (".png", ".jpg", ".jpeg", ".webp", ".tga", ".bmp")
MAX_SHEET = 1024
BAD_PIXEL_WARN = 0.02  # share of inconsistent pixels that triggers a warning


def list_frames(folder):
    if not os.path.isdir(folder):
        raise SystemExit(f"error: {folder} is not a folder")
    names = sorted(n for n in os.listdir(folder) if n.lower().endswith(IMAGE_EXTENSIONS))
    if not names:
        raise SystemExit(f"error: no images in {folder}")
    return [os.path.join(folder, n) for n in names]


def to_square(image, size, fit):
    """Scales an RGBA/RGB image into a size x size square (letterboxed or centre-cropped)."""
    w, h = image.size
    if fit == "crop":
        edge = min(w, h)
        left, top = (w - edge) // 2, (h - edge) // 2
        return image.crop((left, top, left + edge, top + edge)).resize((size, size), Image.LANCZOS)
    scale = size / max(w, h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    resized = image.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new(image.mode, (size, size), (0,) * len(image.getbands()))
    canvas.paste(resized, ((size - nw) // 2, (size - nh) // 2))
    return canvas


def load_pair(black_path, white_path, size, fit):
    """-> (premultiplied RGB image, alpha L image). Black render = premultiplied colour."""
    black = to_square(Image.open(black_path).convert("RGB"), size, fit)
    white = to_square(Image.open(white_path).convert("RGB"), size, fit)
    # Same size and the filter is linear, so scaling first gives the same matte as scaling after.
    # Channel mean (not luma): the three channels carry the same 1 - alpha in a clean pair.
    diff = ImageChops.subtract(white, black).convert("L", (1 / 3, 1 / 3, 1 / 3, 0))
    return black, ImageChops.invert(diff)


def load_rgba(path, size, fit):
    rgba = Image.open(path).convert("RGBA")
    # Premultiply before scaling so transparent pixels don't bleed their colour into edges.
    alpha = rgba.getchannel("A")
    premult = ImageChops.multiply(rgba.convert("RGB"), Image.merge("RGB", (alpha, alpha, alpha)))
    premult = to_square(premult, size, fit)
    alpha = to_square(alpha, size, fit)
    return premult, alpha


def inconsistent_share(premult, alpha, tolerance):
    """Share of pixels whose premultiplied colour exceeds their alpha by more than tolerance."""
    # (premult - alpha) - tolerance, clipped at 0: anything above 0 is a bad pixel
    over = ImageChops.subtract(premult, Image.merge("RGB", (alpha, alpha, alpha)), 1, -tolerance)
    r, g, b = over.split()
    worst = ImageChops.lighter(ImageChops.lighter(r, g), b)
    bad = sum(worst.histogram()[1:])
    return bad / max(1, premult.size[0] * premult.size[1])


def blend(a, b, t):
    return Image.blend(a, b, t)


def loop_blend(frames, count):
    """Cross-fades the last `count` frames toward the first `count` (premultiplied: linear)."""
    n = len(frames)
    count = min(count, n // 2)
    for i in range(count):
        t = (i + 1) / (count + 1)
        premult, alpha = frames[n - count + i]
        first_premult, first_alpha = frames[i]
        frames[n - count + i] = (blend(premult, first_premult, t), blend(alpha, first_alpha, t))
    return frames


def finish(premult, alpha, mode):
    """-> RGBA image with straight alpha (colour = premultiplied / alpha) or white shapes."""
    if mode == "white":
        white = Image.new("RGB", premult.size, (255, 255, 255))
        return Image.merge("RGBA", (*white.split(), alpha))
    out = []
    for (r, g, b), a in zip(premult.getdata(), alpha.getdata()):
        if a == 0:
            out.append((0, 0, 0, 0))
        else:
            k = 255.0 / a
            out.append((min(255, round(r * k)), min(255, round(g * k)), min(255, round(b * k)), a))
    image = Image.new("RGBA", premult.size)
    image.putdata(out)
    return image


def pick(items, count):
    """`count` evenly spaced items (first and last included)."""
    if count >= len(items):
        return list(items)
    if count == 1:
        return [items[0]]
    return [items[round(i * (len(items) - 1) / (count - 1))] for i in range(count)]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--black", help="folder of frames rendered on a pure black background")
    ap.add_argument("--white", help="folder of the same frames on a pure white background")
    ap.add_argument("--rgba", help="folder of frames that already have an alpha channel")
    ap.add_argument("-o", "--out", required=True, help="output folder")
    ap.add_argument("--name", default="Flipbook", help="sheet name prefix (default Flipbook)")
    ap.add_argument("--grid", type=int, choices=(2, 4, 8), default=4)
    ap.add_argument("--sheet-size", type=int, default=1024)
    ap.add_argument("--frames", type=int, help="resample to this many frames")
    ap.add_argument("--skip-first", type=int, default=0)
    ap.add_argument("--loop-blend", type=int, default=0)
    ap.add_argument("--fps", type=float, default=24)
    ap.add_argument("--fit", choices=("pad", "crop"), default="pad")
    ap.add_argument("--color", choices=("keep", "white"), default="keep")
    ap.add_argument("--tolerance", type=int, default=6)
    args = ap.parse_args()

    errors, warnings = [], []
    if args.rgba and (args.black or args.white):
        errors.append("use either --rgba or --black with --white, not both")
    elif not args.rgba and not (args.black and args.white):
        errors.append("give --black and --white (two renders per frame) or --rgba")
    size = args.sheet_size
    if size < 64 or size & (size - 1) or size > MAX_SHEET:
        errors.append(f"--sheet-size {size}: use a power of two from 64 to {MAX_SHEET}")
    if not 20 <= args.fps <= 30:
        warnings.append(f"--fps {args.fps:g}: Roblox flipbooks are normally played at 20-30 frames per second")
    if args.skip_first < 0 or args.loop_blend < 0:
        errors.append("--skip-first and --loop-blend can't be negative")
    if errors:
        for message in errors:
            print(f"error: {message}")
        return 1

    cell = size // args.grid
    if cell < 64:
        warnings.append(f"frames are only {cell} px; use a bigger --sheet-size or a smaller --grid")

    if args.rgba:
        sources = list_frames(args.rgba)
    else:
        blacks, whites = list_frames(args.black), list_frames(args.white)
        if len(blacks) != len(whites):
            print(f"error: {len(blacks)} black frames but {len(whites)} white frames; they must match one to one")
            return 1
        sources = list(zip(blacks, whites))

    sources = sources[args.skip_first:]
    if not sources:
        print("error: --skip-first removed every frame")
        return 1
    sources = pick(sources, args.frames) if args.frames else sources
    per_sheet = args.grid * args.grid

    frames, bad_frames = [], []
    for index, source in enumerate(sources):
        if args.rgba:
            premult, alpha = load_rgba(source, cell, args.fit)
        else:
            premult, alpha = load_pair(source[0], source[1], cell, args.fit)
            if inconsistent_share(premult, alpha, args.tolerance) > BAD_PIXEL_WARN:
                bad_frames.append(index + 1)
        frames.append((premult, alpha))
    if bad_frames:
        shown = ", ".join(str(n) for n in bad_frames[:8]) + (" ..." if len(bad_frames) > 8 else "")
        warnings.append(
            f"matte looks inconsistent in {len(bad_frames)} frame(s) ({shown}): the black and white renders "
            "differ by more than the background (use Standard view transform, no bloom/dither, and keep the "
            "lighting identical in both renders; see references/flipbooks.md)"
        )
    if args.loop_blend:
        if args.loop_blend > len(frames) // 2:
            warnings.append(f"--loop-blend {args.loop_blend} is more than half the frames; using {len(frames) // 2}")
        frames = loop_blend(frames, args.loop_blend)

    os.makedirs(args.out, exist_ok=True)
    sheet_count = math.ceil(len(frames) / per_sheet)
    sheets = []
    for sheet_index in range(sheet_count):
        sheet = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        chunk = frames[sheet_index * per_sheet:(sheet_index + 1) * per_sheet]
        for slot, (premult, alpha) in enumerate(chunk):
            x, y = (slot % args.grid) * cell, (slot // args.grid) * cell
            sheet.paste(finish(premult, alpha, args.color), (x, y))
        file_name = f"{args.name}_{sheet_index + 1}.png"
        sheet.save(os.path.join(args.out, file_name), optimize=True)
        sheets.append({"file": file_name, "frames": len(chunk), "startDelay": round(sheet_index * per_sheet / args.fps, 4)})

    if len(frames) % per_sheet:
        warnings.append(f"{len(frames)} frames fill {sheet_count} sheet(s) of {per_sheet}; the last sheet has "
                        f"{len(frames) % per_sheet} frame(s) and empty cells at the end (use --frames to land on a multiple of {per_sheet})")

    layout = f"Grid{args.grid}x{args.grid}"
    manifest = {
        "name": args.name,
        "frames": len(frames),
        "fps": args.fps,
        "grid": args.grid,
        "frameSize": cell,
        "sheetSize": size,
        "duration": round(len(frames) / args.fps, 4),
        "emitter": {
            "FlipbookLayout": layout,
            "FlipbookMode": "Loop" if args.loop_blend else "OneShot",
            "FlipbookFramerate": args.fps,
            "Lifetime": round(per_sheet / args.fps, 4) if sheet_count > 1 else round(len(frames) / args.fps, 4),
            "Color": "keep the default (white) so the baked colours show" if args.color == "keep" else "tint it with ParticleEmitter.Color",
        },
        "sheets": sheets,
        "notes": ("Longer than one sheet: one emitter per sheet, each Emit(1) after its startDelay, "
                  "Lifetime = sheet frames / fps.") if sheet_count > 1 else "",
    }
    with open(os.path.join(args.out, f"{args.name}.flipbook.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)
        handle.write("\n")

    for message in warnings:
        print(f"warning: {message}")
    print(f"{len(frames)} frames -> {sheet_count} sheet(s) of {layout} at {size}px ({cell}px frames), {args.fps:g} fps, "
          f"{manifest['duration']}s; wrote {args.out}/{args.name}.flipbook.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
