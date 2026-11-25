#!/usr/bin/env python3
"""Packs, checks and previews Roblox particle flipbook sheets (ParticleEmitter.FlipbookLayout).

  flipbook.py pack <frames-dir | frame.png ... | anim.gif> -o sheet.png [--grid 4] [--cell 128]
                   [--margin 4] [--fit] [--white]
  flipbook.py check <sheet.png> [--grid 4] [--margin 4] [--strict]
  flipbook.py preview <sheet.png> -o preview.html [--grid 4] [--fps 16] [--tint #5aaaff ...]

pack     puts the frames in reading order on one transparent grid (Grid2x2 / 4x4 / 8x8 =
         4 / 16 / 64 frames). --fit scales every frame by the SAME factor so the union of their
         contents sits --margin px inside each cell (nothing pops between frames). --white turns
         colored frames into a white mask (alpha = alpha x brightness), so ParticleEmitter.Color
         can tint each layer in game. Animated GIF/APNG/WebP input is read frame by frame.
check    the sheet Roblox gets: square, power of two, <= 1024 px, divisible by the grid; every
         frame keeps its pixels --margin px away from the cell edge (paint on the edge shows as
         a box around the effect), no empty frames, no grey haze filling the cell ("fog
         machine"), white so it can be tinted. Exit 1 on errors (and on warnings with --strict).
preview  one HTML file: the frame playing on the left (tinted per --tint, on dark and light
         backgrounds), the sheet on the right with the frame on show lit up, play/pause/step.

Needs Pillow.
"""

import argparse
import base64
import glob
import html
import io
import json
import os
import sys

from PIL import Image, ImageChops, ImageSequence

LAYOUTS = {2: "Grid2x2", 4: "Grid4x4", 8: "Grid8x8"}
MAX_SIZE = 1024
EMPTY_ALPHA = 8  # a frame whose strongest pixel is below this is empty
HAZE_ALPHA = (4, 48)  # faint pixels in this range...
HAZE_SHARE = 0.45  # ...covering this share of a cell = grey haze around the shape
COLOR_SPREAD = 24  # max(r,g,b) - min(r,g,b) above this on a visible pixel = colored, not white


class Report:
    def __init__(self):
        self.lines = []

    def add(self, level, where, message):
        self.lines.append((level, where, message))

    def count(self, level):
        return sum(1 for line in self.lines if line[0] == level)

    def print(self):
        for level, where, message in self.lines:
            print(f"{level:<5} {where}: {message}")


# ---------------------------------------------------------------- frames in


def load_frames(inputs):
    """Frames as RGBA images from a directory, a list of files, or one animated file."""
    paths = []
    for item in inputs:
        if os.path.isdir(item):
            found = [p for p in glob.glob(os.path.join(item, "*")) if p.lower().endswith((".png", ".gif", ".webp"))]
            paths += sorted(found)
        else:
            paths.append(item)
    frames = []
    for path in paths:
        with Image.open(path) as image:
            if getattr(image, "is_animated", False):
                frames += [frame.convert("RGBA") for frame in ImageSequence.Iterator(image)]
            else:
                frames.append(image.convert("RGBA"))
    return frames


def to_white(frame):
    """White mask: alpha = alpha x brightness (max channel), color = white."""
    r, g, b, a = frame.split()
    brightness = ImageChops.lighter(ImageChops.lighter(r, g), b)
    alpha = ImageChops.multiply(a, brightness)
    white = Image.new("RGBA", frame.size, (255, 255, 255, 0))
    white.putalpha(alpha)
    return white


def union_bbox(frames):
    box = None
    for frame in frames:
        b = frame.getchannel("A").point(lambda v: 255 if v >= EMPTY_ALPHA else 0).getbbox()
        if b is None:
            continue
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    return box


def pack(frames, grid, cell, margin=4, fit=False, white=False):
    """Returns the sheet (RGBA, grid*cell square) and notes about what was done."""
    notes = []
    count = grid * grid
    if not frames:
        raise ValueError("no frames")
    if len(frames) > count:
        raise ValueError(f"{len(frames)} frames do not fit a {grid}x{grid} grid ({count} max); use a bigger grid or fewer frames")
    if len(frames) < count:
        notes.append(f"{len(frames)} frames for {count} cells: the last {count - len(frames)} cell(s) stay empty")
    if white:
        frames = [to_white(f) for f in frames]
    sizes = {f.size for f in frames}
    if len(sizes) > 1:
        raise ValueError(f"frames differ in size: {sorted(sizes)}")
    width, height = frames[0].size
    if fit:
        box = union_bbox(frames)
        if box is None:
            raise ValueError("every frame is empty")
        inner = cell - 2 * margin
        bw, bh = box[2] - box[0], box[3] - box[1]
        factor = min(inner / bw, inner / bh)
        cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
        notes.append(f"fit: content {bw}x{bh} px scaled x{factor:.3f} into {inner}x{inner}")
        placed = []
        for frame in frames:
            scaled = frame.resize((max(1, round(width * factor)), max(1, round(height * factor))), Image.LANCZOS)
            canvas = Image.new("RGBA", (cell, cell), (255, 255, 255, 0))
            canvas.paste(scaled, (round(cell / 2 - cx * factor), round(cell / 2 - cy * factor)), scaled)
            placed.append(canvas)
        frames = placed
    elif (width, height) != (cell, cell):
        notes.append(f"frames {width}x{height} resized to {cell}x{cell}")
        frames = [f.resize((cell, cell), Image.LANCZOS) for f in frames]
    sheet = Image.new("RGBA", (grid * cell, grid * cell), (255, 255, 255, 0))
    for index, frame in enumerate(frames):
        sheet.paste(frame, ((index % grid) * cell, (index // grid) * cell))
    return sheet, notes


# ---------------------------------------------------------------- checks


def frame_boxes(sheet, grid):
    cell = sheet.width // grid
    return [(i, ((i % grid) * cell, (i // grid) * cell, (i % grid + 1) * cell, (i // grid + 1) * cell)) for i in range(grid * grid)]


def check(sheet, grid, margin, report, name="sheet"):
    w, h = sheet.size
    if w != h:
        report.add("ERROR", name, f"{w}x{h}: flipbook sheets must be square")
    if w & (w - 1) or h & (h - 1):
        report.add("ERROR", name, f"{w}x{h}: use a power-of-two size (256, 512, 1024)")
    if max(w, h) > MAX_SIZE:
        report.add("ERROR", name, f"{w}x{h}: Roblox downscales textures over {MAX_SIZE} px; frames lose detail")
    if w % grid or h % grid:
        report.add("ERROR", name, f"{w}x{h} does not divide into a {grid}x{grid} grid")
    if report.count("ERROR"):
        return []
    if sheet.mode != "RGBA":
        report.add("ERROR", name, f"mode {sheet.mode}: needs an alpha channel (transparent background)")
        return []
    cell = w // grid
    if cell < 32:
        report.add("WARN", name, f"{cell} px frames are very small")
    stats = []
    colored_frames = []
    empty_frames = []
    for index, box in frame_boxes(sheet, grid):
        frame = sheet.crop(box)
        where = f"frame {index + 1} (row {index // grid + 1}, col {index % grid + 1})"
        alpha = frame.getchannel("A")
        strongest = alpha.getextrema()[1]
        if strongest < EMPTY_ALPHA:
            empty_frames.append(index + 1)
            stats.append({"frame": index + 1, "empty": True})
            continue
        visible = alpha.point(lambda v: 255 if v >= EMPTY_ALPHA else 0)
        content = visible.getbbox()
        any_alpha = alpha.point(lambda v: 255 if v > 0 else 0).getbbox()
        gap = min(any_alpha[0], any_alpha[1], cell - any_alpha[2], cell - any_alpha[3])
        if gap < margin:
            sides = [
                side
                for side, d in (("left", any_alpha[0]), ("top", any_alpha[1]), ("right", cell - any_alpha[2]), ("bottom", cell - any_alpha[3]))
                if d < margin
            ]
            level = "ERROR" if gap == 0 else "WARN"
            report.add(level, where, f"paint {gap} px from the {'/'.join(sides)} edge (keep {margin} px clear, or the cell shows as a box)")
        hist = alpha.histogram()
        faint = sum(hist[HAZE_ALPHA[0] : HAZE_ALPHA[1] + 1])
        if faint / (cell * cell) >= HAZE_SHARE:
            report.add("WARN", where, f"{round(100 * faint / (cell * cell))}% of the cell is faint haze; cut smoke/fog around the shape")
        r, g, b, _ = frame.split()
        spread = ImageChops.subtract(ImageChops.lighter(ImageChops.lighter(r, g), b), ImageChops.darker(ImageChops.darker(r, g), b))
        colored = ImageChops.multiply(spread.point(lambda v: 255 if v > COLOR_SPREAD else 0), visible)
        if colored.getbbox():
            colored_frames.append(index + 1)
        stats.append({"frame": index + 1, "empty": False, "bbox": list(content or any_alpha), "edgeGap": gap})
    runs = []  # consecutive empty frames, reported as one line each
    for number in empty_frames:
        if runs and runs[-1][1] == number - 1:
            runs[-1][1] = number
        else:
            runs.append([number, number])
    for first, last in runs:
        cells = f"frame {first} (row {(first - 1) // grid + 1}, col {(first - 1) % grid + 1})" if first == last else f"frames {first}-{last}"
        report.add("ERROR", cells, "empty: nothing visible (OneShot plays every cell over the lifetime, so the effect blinks out)")
    if colored_frames:
        listed = ", ".join(str(i) for i in colored_frames[:6]) + (" ..." if len(colored_frames) > 6 else "")
        report.add("WARN", name, f"colored pixels in frame(s) {listed}: draw in white (pack --white) so ParticleEmitter.Color tints every layer")
    return stats


# ---------------------------------------------------------------- preview


def data_uri(image):
    buffer = io.BytesIO()
    image.save(buffer, "PNG")
    return "data:image/png;base64," + base64.b64encode(buffer.getvalue()).decode()


def write_preview(path, sheet, grid, fps, tints, stats, report, title):
    cell = sheet.width // grid
    shown = 192
    problems = [(level, where, message) for level, where, message in report.lines]
    tints = tints or ["#ffffff"]
    players = "".join(
        f"<div class='player {bg}'><div class='frame' data-tint='{html.escape(t)}' style='--tint:{html.escape(t)}'></div>"
        f"<span>{html.escape(t)} on {bg}</span></div>"
        for t in tints
        for bg in ("dark", "light")
    )
    rows = "".join(f"<li class='{level.lower()}'><b>{level}</b> {html.escape(where)}: {html.escape(message)}</li>" for level, where, message in problems) or "<li class='ok'>no problems found</li>"
    page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Flipbook preview</title><style>
:root{{color-scheme:dark;--bg:#14161b;--panel:#1d2028;--ink:#e8eaf0;--muted:#9aa0ad;--hot:#ffd34d}}
body{{margin:0;padding:16px;background:var(--bg);color:var(--ink);font:14px/1.45 system-ui,sans-serif}}
h1{{font-size:18px;margin:0 0 4px}} p{{color:var(--muted);margin:0 0 12px}}
.wrap{{display:flex;flex-wrap:wrap;gap:16px;align-items:flex-start}}
.players{{display:grid;grid-template-columns:repeat(2,minmax(0,{shown}px));gap:10px;flex:1 1 300px;max-width:{2 * shown + 10}px}}
.player span{{display:block;font-size:12px;color:var(--muted);margin-top:4px}}
.player.dark .frame{{background-color:#0c0d10}} .player.light .frame{{background-color:#c9ced8}}
.frame{{width:100%;aspect-ratio:1;border-radius:6px;position:relative;overflow:hidden}}
.frame::after{{content:"";position:absolute;inset:0;background:var(--tint);
  -webkit-mask:var(--cell) var(--pos)/var(--sz) no-repeat;mask:var(--cell) var(--pos)/var(--sz) no-repeat}}
.sheetbox{{position:relative;width:min(512px,100%);aspect-ratio:1;background:#0c0d10 linear-gradient(45deg,#1b1e25 25%,transparent 25%,transparent 75%,#1b1e25 75%) 0 0/16px 16px}}
.sheetbox img{{width:100%;height:100%;display:block;image-rendering:auto}}
.grid{{position:absolute;inset:0;display:grid;grid-template-columns:repeat({grid},1fr)}}
.grid div{{outline:1px solid #ffffff26;font-size:11px;color:var(--muted);padding:2px 4px}}
.grid div.on{{outline:3px solid var(--hot);color:var(--hot);background:#ffd34d14}}
.controls{{margin:12px 0;display:flex;gap:8px;align-items:center;flex-wrap:wrap}}
button{{background:var(--panel);color:var(--ink);border:1px solid #333847;border-radius:6px;padding:6px 12px;font:inherit;cursor:pointer}}
ul{{padding-left:18px}} li.error b{{color:#ff6b6b}} li.warn b{{color:var(--hot)}} li.ok{{color:#7ee2a8}}
</style></head><body>
<h1>Flipbook preview: {html.escape(title)}</h1>
<p>{sheet.width}x{sheet.height} px, {grid}x{grid} = {grid * grid} frames of {cell} px, FlipbookLayout {LAYOUTS.get(grid, '?')}. Left: the frame on show, tinted like ParticleEmitter.Color does. Right: the sheet with that frame lit up.</p>
<div class="controls"><button id="play">Pause</button><button id="prev">&larr; frame</button><button id="next">frame &rarr;</button>
<label>fps <input id="fps" type="number" min="1" max="60" value="{fps}" style="width:56px"></label><span id="label"></span></div>
<div class="wrap"><div class="players">{players}</div>
<div class="sheetbox"><img id="sheet" alt="flipbook sheet" src="{data_uri(sheet)}"><div class="grid" id="grid"></div></div></div>
<h2 style="font-size:15px">Check</h2><ul>{rows}</ul>
<script>
const GRID={grid}, N=GRID*GRID, STATS={json.dumps(stats)};
const src=document.getElementById('sheet').src, grid=document.getElementById('grid');
for(let i=0;i<N;i++){{const d=document.createElement('div');d.textContent=i+1;grid.appendChild(d);}}
const frames=[...document.querySelectorAll('.frame')];
frames.forEach(f=>{{f.style.setProperty('--cell',`url(${{src}})`);f.style.setProperty('--sz',`${{GRID*100}}% ${{GRID*100}}%`);}});
let i=0, playing=true, timer=null;
function show(){{
  const x=(i%GRID)*100/(GRID-1), y=Math.floor(i/GRID)*100/(GRID-1);  // % positions: cell k of N sits at k/(N-1)
  frames.forEach(f=>f.style.setProperty('--pos',`${{x}}% ${{y}}%`));
  [...grid.children].forEach((d,k)=>d.classList.toggle('on',k===i));
  const s=STATS[i]||{{}};
  document.getElementById('label').textContent=`frame ${{i+1}}/${{N}}`+(s.empty?' (empty)':s.edgeGap!==undefined?`, ${{s.edgeGap}} px to the edge`:'');
}}
function tick(){{i=(i+1)%N;show();}}
function run(){{clearInterval(timer);if(playing)timer=setInterval(tick,1000/Math.max(1,+document.getElementById('fps').value||{fps}));}}
document.getElementById('play').onclick=e=>{{playing=!playing;e.target.textContent=playing?'Pause':'Play';run();}};
document.getElementById('prev').onclick=()=>{{i=(i+N-1)%N;show();}};
document.getElementById('next').onclick=()=>{{i=(i+1)%N;show();}};
document.getElementById('fps').onchange=run;
const q=new URLSearchParams(location.search); if(q.has('frame')){{i=Math.min(N-1,Math.max(0,(+q.get('frame')||1)-1));playing=false;document.getElementById('play').textContent='Play';}}
show();run();
</script></body></html>"""
    with open(path, "w", encoding="utf-8") as f:
        f.write(page)


# ---------------------------------------------------------------- CLI


def grid_arg(value):
    grid = int(value)
    if grid not in LAYOUTS:
        raise argparse.ArgumentTypeError("grid must be 2, 4 or 8 (Grid2x2 / Grid4x4 / Grid8x8)")
    return grid


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)
    p = sub.add_parser("pack", help="frames -> sheet")
    p.add_argument("inputs", nargs="+")
    p.add_argument("-o", "--out", required=True)
    p.add_argument("--grid", type=grid_arg, default=4)
    p.add_argument("--cell", type=int, default=128, help="frame size in px (sheet = grid x cell)")
    p.add_argument("--margin", type=int, default=4)
    p.add_argument("--fit", action="store_true", help="scale all frames alike so the content keeps the margin")
    p.add_argument("--white", action="store_true", help="convert to a white mask for tinting")
    c = sub.add_parser("check", help="check a sheet")
    c.add_argument("sheet")
    c.add_argument("--grid", type=grid_arg, default=4)
    c.add_argument("--margin", type=int, default=4)
    c.add_argument("--strict", action="store_true", help="exit 1 on warnings too")
    c.add_argument("--json", help="write per-frame stats here")
    v = sub.add_parser("preview", help="HTML preview of a sheet")
    v.add_argument("sheet")
    v.add_argument("-o", "--out", required=True)
    v.add_argument("--grid", type=grid_arg, default=4)
    v.add_argument("--margin", type=int, default=4)
    v.add_argument("--fps", type=int, default=16)
    v.add_argument("--tint", action="append", help="CSS color to tint with, repeatable (one per variant)")
    args = ap.parse_args()

    if args.command == "pack":
        try:
            sheet, notes = pack(load_frames(args.inputs), args.grid, args.cell, args.margin, args.fit, args.white)
        except (ValueError, OSError) as error:
            print(f"ERROR {error}")
            return 1
        for note in notes:
            print(f"note  {note}")
        sheet.save(args.out, optimize=True)
        print(f"wrote {args.out} ({sheet.width}x{sheet.height}, {LAYOUTS[args.grid]})")
        report = Report()
        check(sheet, args.grid, args.margin, report, os.path.basename(args.out))
        report.print()
        print(f"{report.count('ERROR')} error(s), {report.count('WARN')} warning(s)")
        return 1 if report.count("ERROR") else 0

    with Image.open(args.sheet) as image:
        image.load()
        sheet = image
    report = Report()
    stats = check(sheet, args.grid, args.margin, report, os.path.basename(args.sheet))
    if args.command == "check":
        report.print()
        print(f"{report.count('ERROR')} error(s), {report.count('WARN')} warning(s)")
        if args.json:
            with open(args.json, "w", encoding="utf-8") as f:
                json.dump(stats, f, indent=1)
        return 1 if report.count("ERROR") or (args.strict and report.count("WARN")) else 0
    if sheet.mode != "RGBA":
        sheet = sheet.convert("RGBA")
    write_preview(args.out, sheet, args.grid, args.fps, args.tint, stats, report, os.path.basename(args.sheet))
    print(f"preview: {args.out} ({report.count('ERROR')} error(s), {report.count('WARN')} warning(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
