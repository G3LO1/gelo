#!/usr/bin/env python3
"""Tests for scripts/pack_flipbook.py: builds synthetic effect frames with a known colour and
alpha, renders them on black and on white, packs them and checks that the cut-out, the sheet
layout, the options and the error paths behave. Needs python3 + pillow.

Usage (repo root): python3 tests/roblox-animation-vfx/flipbook_test.py <pack_flipbook.py> <tmp dir>
"""

import json
import math
import os
import subprocess
import sys

from PIL import Image

script, tmp = sys.argv[1], sys.argv[2]
passed = failed = 0
SIZE = 256  # source frame edge = the cell edge of a 1024 px sheet at grid 4, so nothing is rescaled
COLOR = (255, 120, 20)


def check(condition, message):
    global passed, failed
    if condition:
        passed += 1
        print(f"  ok   {message}")
    else:
        failed += 1
        print(f"  FAIL {message}")


def alpha_at(frame, x, y):
    """Soft disc growing with the frame number, so every frame differs."""
    radius = 20 + frame * 5
    distance = math.hypot(x - SIZE / 2, y - SIZE / 2)
    return max(0.0, min(1.0, (radius - distance) / 12))


def make_frames(folder_black, folder_white, folder_rgba, count):
    for folder in (folder_black, folder_white, folder_rgba):
        os.makedirs(folder, exist_ok=True)
    for frame in range(count):
        black, white, rgba = (Image.new(mode, (SIZE, SIZE)) for mode in ("RGB", "RGB", "RGBA"))
        pb, pw, pr = black.load(), white.load(), rgba.load()
        for y in range(SIZE):
            for x in range(SIZE):
                a = alpha_at(frame, x, y)
                pb[x, y] = tuple(round(c * a) for c in COLOR)
                pw[x, y] = tuple(round(c * a + 255 * (1 - a)) for c in COLOR)
                pr[x, y] = (*COLOR, round(a * 255))
        name = f"f{frame:03d}.png"
        black.save(os.path.join(folder_black, name))
        white.save(os.path.join(folder_white, name))
        rgba.save(os.path.join(folder_rgba, name))


def run(*args):
    result = subprocess.run([sys.executable, script, *args], capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr


def sheet_cell(path, slot, grid=4, cell=SIZE):
    sheet = Image.open(path)
    x, y = (slot % grid) * cell, (slot // grid) * cell
    return sheet.crop((x, y, x + cell, y + cell))


black, white, rgba = (os.path.join(tmp, name) for name in ("black", "white", "rgba"))
make_frames(black, white, rgba, 20)

print("pack_flipbook.py: black/white matte")
out = os.path.join(tmp, "out20")
code, text = run("--black", black, "--white", white, "-o", out, "--name", "Blast", "--fps", "24")
check(code == 0, "exits 0")
check(os.path.exists(f"{out}/Blast_1.png") and os.path.exists(f"{out}/Blast_2.png") and not os.path.exists(f"{out}/Blast_3.png"),
      "20 frames -> 2 sheets of 16")
check("last sheet has 4 frame(s)" in text, "warns that the last sheet is not full")
check(Image.open(f"{out}/Blast_1.png").size == (1024, 1024), "sheet is 1024x1024")
manifest = json.load(open(f"{out}/Blast.flipbook.json"))
check(manifest["frames"] == 20 and manifest["emitter"]["FlipbookLayout"] == "Grid4x4" and manifest["emitter"]["FlipbookFramerate"] == 24,
      "manifest has frames, layout and framerate")
check([s["frames"] for s in manifest["sheets"]] == [16, 4] and abs(manifest["sheets"][1]["startDelay"] - 16 / 24) < 1e-3,
      "second sheet starts after the first")
check(manifest["emitter"]["FlipbookMode"] == "OneShot" and manifest["emitter"]["Lifetime"] == round(16 / 24, 4),
      "one-shot mode, lifetime = sheet frames / fps")

cell = sheet_cell(f"{out}/Blast_1.png", 5)  # frame 5
worst_alpha = worst_color = 0
for y in range(0, SIZE, 7):
    for x in range(0, SIZE, 7):
        r, g, b, a = cell.getpixel((x, y))
        expected = round(alpha_at(5, x, y) * 255)
        worst_alpha = max(worst_alpha, abs(a - expected))
        if expected > 128:  # colour is only meaningful where there is something to see
            worst_color = max(worst_color, abs(r - COLOR[0]), abs(g - COLOR[1]), abs(b - COLOR[2]))
check(worst_alpha <= 2, f"alpha recovered from the black/white pair (worst error {worst_alpha}/255)")
check(worst_color <= 6, f"colour un-premultiplied (worst error {worst_color}/255 where alpha > 50%)")
check(sheet_cell(f"{out}/Blast_1.png", 0).getpixel((0, 0))[3] == 0, "background is fully transparent")
check(sheet_cell(f"{out}/Blast_2.png", 5).getchannel("A").getbbox() is None, "unused cells in the last sheet are empty")

print("pack_flipbook.py: options")
out = os.path.join(tmp, "out16")
code, text = run("--black", black, "--white", white, "-o", out, "--name", "Blast", "--frames", "16", "--skip-first", "2")
check(code == 0 and "last sheet" not in text and not os.path.exists(f"{out}/Blast_2.png"), "--frames 16 -> one full sheet")
# skip 2 of 20 leaves frames 2..19, resampled to 16 evenly: first picked frame is frame 2
first = sheet_cell(f"{out}/Blast_1.png", 0)
expected_a = round(alpha_at(2, SIZE / 2, SIZE / 2 - 30) * 255)
check(abs(first.getpixel((SIZE // 2, SIZE // 2 - 30))[3] - expected_a) <= 2, "--skip-first drops the warm-up frames")

out = os.path.join(tmp, "outwhite")
code, _ = run("--black", black, "--white", white, "-o", out, "--name", "W", "--frames", "16", "--color", "white")
r, g, b, a = sheet_cell(f"{out}/W_1.png", 3).getpixel((SIZE // 2, SIZE // 2))
check(code == 0 and (r, g, b) == (255, 255, 255) and a > 200, "--color white outputs white shapes with alpha")

out = os.path.join(tmp, "outloop")
code, _ = run("--black", black, "--white", white, "-o", out, "--name", "L", "--frames", "16", "--loop-blend", "3")
manifest = json.load(open(f"{out}/L.flipbook.json"))
last = sheet_cell(f"{out}/L_1.png", 15).getpixel((SIZE // 2, SIZE // 2 + 60))[3]
raw_last = round(alpha_at(19, SIZE // 2, SIZE // 2 + 60) * 255)
raw_first = round(alpha_at(0, SIZE // 2, SIZE // 2 + 60) * 255)
check(code == 0 and manifest["emitter"]["FlipbookMode"] == "Loop", "--loop-blend sets Loop mode")
check(raw_first <= last < raw_last, f"--loop-blend pulls the last frame toward the first ({raw_last} -> {last})")

out = os.path.join(tmp, "outrgba")
code, _ = run("--rgba", rgba, "-o", out, "--name", "R", "--frames", "16")
cell = sheet_cell(f"{out}/R_1.png", 7)
a_expected = round(alpha_at(round(7 * 19 / 15), SIZE // 2, SIZE // 2) * 255)
check(code == 0 and abs(cell.getpixel((SIZE // 2, SIZE // 2))[3] - a_expected) <= 2, "--rgba packs frames that already have alpha")

print("pack_flipbook.py: errors and warnings")
os.makedirs(os.path.join(tmp, "short"), exist_ok=True)
Image.new("RGB", (SIZE, SIZE)).save(os.path.join(tmp, "short", "f000.png"))
code, text = run("--black", black, "--white", os.path.join(tmp, "short"), "-o", os.path.join(tmp, "x"))
check(code == 1 and "20 black frames but 1 white frames" in text, "mismatched black/white frame counts are an error")
code, text = run("--black", black, "--white", white, "-o", os.path.join(tmp, "x"), "--sheet-size", "1000")
check(code == 1 and "power of two" in text, "sheet size must be a power of two")
code, text = run("--black", black, "--white", white, "-o", os.path.join(tmp, "x"), "--sheet-size", "2048")
check(code == 1 and "1024" in text, "sheets above 1024 px are refused")
code, text = run("-o", os.path.join(tmp, "x"))
check(code == 1 and "--black and --white" in text, "needs an input")
code, text = run("--black", black, "--white", white, "-o", os.path.join(tmp, "x"), "--fps", "60", "--frames", "16")
check(code == 0 and "20-30 frames per second" in text, "unusual fps is a warning")

bad_black, bad_white = os.path.join(tmp, "bad_black"), os.path.join(tmp, "bad_white")
os.makedirs(bad_black, exist_ok=True)
os.makedirs(bad_white, exist_ok=True)
Image.new("RGB", (SIZE, SIZE), (250, 0, 0)).save(os.path.join(bad_black, "f000.png"))
Image.new("RGB", (SIZE, SIZE), (255, 255, 255)).save(os.path.join(bad_white, "f000.png"))
code, text = run("--black", bad_black, "--white", bad_white, "-o", os.path.join(tmp, "x"))
check(code == 0 and "matte looks inconsistent in 1 frame" in text, "inconsistent black/white pair is flagged")

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
