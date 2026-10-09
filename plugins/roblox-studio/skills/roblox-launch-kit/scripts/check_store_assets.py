#!/usr/bin/env python3
"""Checks a Roblox game's store page assets before upload and renders a preview.

Usage:
  check_store_assets.py <store-dir> [--preview preview.html] [--strict]
  check_store_assets.py --icon icon.png --thumbs a.png b.jpg --title-text "Name" --description desc.txt

<store-dir> layout (all optional, checked if present):
  icon.(png|jpg)        game icon
  thumbnails/*          thumbnail images, in upload order
  title.txt             game name (one line)
  description.txt       description

Errors break upload rules (wrong format, over 3 MB, over 1,000 characters, more than 10
thumbnails, non-square icon); warnings are documented best practices or heuristics
(resolution, 16:9, busy bottom edge under the player-count overlay, low contrast at 150 px,
near-duplicate thumbnails, giveaway bait, hashtags, control lists). Exit code 1 on errors
(also on warnings with --strict). Needs Pillow.
"""

import argparse
import base64
import glob
import html
import io
import os
import re
import sys

try:
    from PIL import Image, ImageFilter, ImageStat
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: pip install pillow")

THUMB_FORMATS = {".jpg", ".jpeg", ".gif", ".png", ".tga", ".bmp"}
ICON_FORMATS = {".jpg", ".jpeg", ".png", ".gif", ".tga", ".bmp"}
MAX_THUMB_BYTES = 3 * 1024 * 1024
MAX_THUMBS = 10
DESCRIPTION_LIMIT = 1000
HOOK_LENGTH = 160
BAIT = re.compile(r"\b(free\s+robux|robux|giveaways?|free\s+ugc|free\s+items?|free\s+admin|\d+\s*%\s*off)\b", re.I)
CONTROLS = re.compile(r"\b(wasd|press\s+[a-z0-9]\b|shift\s+to|left\s+click|right\s+click|controls?\s*:|keybinds?)", re.I)
EMOJI = re.compile("[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U0001F000-\U0001F2FF]")


class Report:
    def __init__(self):
        self.items = []

    def error(self, where, message):
        self.items.append(("ERROR", where, message))

    def warn(self, where, message):
        self.items.append(("WARN", where, message))

    def info(self, where, message):
        self.items.append(("INFO", where, message))

    def count(self, level):
        return sum(1 for item in self.items if item[0] == level)


def luminance_std(image, size):
    small = image.convert("L").resize(size, Image.LANCZOS)
    return ImageStat.Stat(small).stddev[0] / 255


def average_hash(image):
    small = image.convert("L").resize((16, 9), Image.LANCZOS)
    pixels = list(small.tobytes())
    mean = sum(pixels) / len(pixels)
    return [p > mean for p in pixels]


def flatten(image):
    if image.mode in ("RGBA", "LA", "P"):
        rgba = image.convert("RGBA")
        background = Image.new("RGBA", rgba.size, (128, 128, 128, 255))
        background.alpha_composite(rgba)
        return background.convert("RGB")
    return image.convert("RGB")


def check_icon(path, report):
    where = os.path.basename(path)
    ext = os.path.splitext(path)[1].lower()
    if ext not in ICON_FORMATS:
        report.error(where, f"unsupported icon format {ext}")
        return None
    try:
        image = Image.open(path)
        image.load()
    except Exception as exc:  # noqa: BLE001
        report.error(where, f"can't read image: {exc}")
        return None
    w, h = image.size
    if abs(w - h) > max(w, h) * 0.01:
        report.error(where, f"icon must be square, got {w}x{h}")
    if min(w, h) < 512:
        report.warn(where, f"icon is {w}x{h}; use at least 512x512 so it stays sharp")
    flat = flatten(image)
    contrast = luminance_std(flat, (150, 150))
    if contrast < 0.12:
        report.warn(where, f"low contrast at 150x150 (luminance spread {contrast:.2f}); the icon may read as a flat blob on Home (heuristic)")
    report.info(where, f"{w}x{h}, {os.path.getsize(path) // 1024} KB, contrast at 150 px {contrast:.2f}")
    return flat


def check_thumbnail(path, report, index):
    where = f"thumbnail {index + 1} ({os.path.basename(path)})"
    ext = os.path.splitext(path)[1].lower()
    if ext not in THUMB_FORMATS:
        report.error(where, f"unsupported format {ext} (use .jpg .png .gif .tga .bmp)")
        return None
    size = os.path.getsize(path)
    if size > MAX_THUMB_BYTES:
        report.error(where, f"{size / 1048576:.1f} MB; Home page thumbnails must be under 3 MB (export as .jpg)")
    try:
        image = Image.open(path)
        image.load()
    except Exception as exc:  # noqa: BLE001
        report.error(where, f"can't read image: {exc}")
        return None
    w, h = image.size
    if abs(w / h - 16 / 9) > 0.02:
        report.warn(where, f"{w}x{h} is not 16:9; Roblox stretches it to 16:9")
    if w < 1920 or h < 1080:
        report.warn(where, f"{w}x{h}; 1920x1080 keeps it sharp everywhere")
    flat = flatten(image)
    edges = flat.convert("L").resize((384, 216), Image.LANCZOS).filter(ImageFilter.FIND_EDGES)
    data = edges.tobytes()
    rows = [data[y * 384:(y + 1) * 384] for y in range(216)]
    row_means = [sum(r) / len(r) for r in rows]
    overall = sum(row_means) / len(row_means)
    bottom = sum(row_means[int(216 * 0.85):]) / len(row_means[int(216 * 0.85):])
    if overall > 1 and bottom > overall * 1.6 and bottom > 12:
        report.warn(where, "the bottom 15% is busier than the rest; text or key details there can sit under the player-count overlay (heuristic)")
    report.info(where, f"{w}x{h}, {size // 1024} KB")
    return flat


def check_title(title, report):
    where = "title"
    words = re.findall(r"[^\W\d_]+", title.lower())
    counts = {}
    for word in words:
        counts[word] = counts.get(word, 0) + 1
    repeated = [w for w, c in counts.items() if c >= 3 or (c >= 2 and len(w) > 3)]
    if repeated:
        report.warn(where, f"repeated word(s) {', '.join(repeated)}: repetition gets games demoted")
    emojis = EMOJI.findall(title)
    if len(emojis) > 2:
        report.warn(where, f"{len(emojis)} emojis; one or two well-placed ones at most")
    letters = [c for c in title if c.isalpha()]
    if letters and sum(c.isupper() for c in letters) / len(letters) > 0.6 and len(letters) > 6:
        report.warn(where, "mostly capital letters reads as spam")
    if BAIT.search(title):
        report.warn(where, f"'{BAIT.search(title).group(0)}' in the name: metadata leading with giveaways/Robux is not prioritized for recommendations")
    if len(title) > 40:
        report.warn(where, f"{len(title)} characters; long names get cut on tiles (heuristic)")
    report.info(where, f"{title!r}, {len(title)} characters")


def check_description(text, title, report):
    where = "description"
    length = len(text)
    if length > DESCRIPTION_LIMIT:
        report.error(where, f"{length} characters, limit is {DESCRIPTION_LIMIT}")
    hook = text.strip()[:HOOK_LENGTH]
    core = re.sub(r"[^\w ]", "", (title or "").lower()).strip()
    core_words = [w for w in core.split() if len(w) > 2]
    if core_words and not any(w in hook.lower() for w in core_words):
        report.warn(where, "the first 160 characters (search snippet and collapsed mobile text) don't mention the game's name")
    if re.search(r"(^|\s)#\w+", text):
        report.warn(where, "hashtags/tags are unused by ranking and only eat characters")
    if CONTROLS.search(text):
        report.warn(where, f"lists controls ('{CONTROLS.search(text).group(0)}'); teach controls in the game instead")
    if BAIT.search(text):
        report.warn(where, f"'{BAIT.search(text).group(0)}': giveaway/Robux promises in metadata reduce recommendations")
    report.info(where, f"{length}/{DESCRIPTION_LIMIT} characters; hook: {hook!r}")


def data_uri(image, size=None, fmt="JPEG"):
    image = image.copy()
    if size:
        image = image.resize(size, Image.LANCZOS)
    buffer = io.BytesIO()
    image.save(buffer, fmt, quality=88)
    return f"data:image/{fmt.lower()};base64," + base64.b64encode(buffer.getvalue()).decode()


def write_preview(path, icon, thumbs, title, description, report):
    rows = []
    for level, where, message in report.items:
        if level != "INFO":
            rows.append(f"<li class='{level.lower()}'><b>{level}</b> {html.escape(where)}: {html.escape(message)}</li>")
    icon_html = ""
    if icon is not None:
        sizes = [(512, 256, "512 px upload (shown at 256)"), (150, 150, "150 px (Home tile)"), (64, 64, "64 px (smallest lists)")]
        cells = "".join(
            f"<figure><img src='{data_uri(icon, (s, s))}' width='{shown}' height='{shown}' style='border-radius:{shown // 8}px'><figcaption>{c}</figcaption></figure>"
            for s, shown, c in sizes
        )
        icon_html = f"<h2>Icon</h2><div class='row light'>{cells}</div><div class='row dark'>{cells}</div>"
    tiles = ""
    for i, thumb in enumerate(thumbs):
        if thumb is None:
            continue
        tiles += (
            f"<figure class='tile'><div class='frame'><img src='{data_uri(thumb, (640, 360))}'>"
            f"<div class='overlay'>&#128077; 92% &nbsp; &#128101; 1.2K playing</div></div>"
            f"<figcaption>{i + 1}. {html.escape(title or 'Game name')}</figcaption></figure>"
        )
    hook = html.escape((description or "").strip()[:HOOK_LENGTH])
    rest = html.escape((description or "").strip()[HOOK_LENGTH:])
    page = f"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Store preview</title><style>
body{{font-family:system-ui,sans-serif;margin:0;padding:16px;background:#f2f3f5;color:#1b1d21}}
h1{{font-size:20px}} h2{{font-size:16px;margin-top:28px}}
.row{{display:flex;gap:24px;align-items:flex-end;flex-wrap:wrap;padding:16px;border-radius:12px}}
.light{{background:#fff}} .dark{{background:#232527;color:#eee;margin-top:8px}}
figure{{margin:0}} figcaption{{font-size:12px;margin-top:6px}}
.tiles{{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:16px}}
.frame{{position:relative;aspect-ratio:16/9;border-radius:10px;overflow:hidden;background:#000}}
.frame img{{width:100%;height:100%;object-fit:fill;display:block}}
.overlay{{position:absolute;left:0;right:0;bottom:0;height:15%;background:rgba(0,0,0,.55);color:#fff;font-size:12px;display:flex;align-items:center;padding-left:10px}}
.desc{{background:#fff;border-radius:12px;padding:16px;max-width:640px;white-space:pre-wrap}}
.hook{{font-weight:600}} .more{{color:#888}}
li.error{{color:#b3261e}} li.warn{{color:#8a5a00}}
</style></head><body>
<h1>Store preview: {html.escape(title or '(no title)')}</h1>
<ul>{''.join(rows) or '<li>No errors or warnings.</li>'}</ul>
{icon_html}
<h2>Thumbnails as Home tiles (bottom 15% = where metadata can cover them)</h2><div class="tiles">{tiles or '<p>No thumbnails.</p>'}</div>
<h2>Description (bold = the first 160 characters shown in search and collapsed on mobile)</h2>
<div class="desc"><span class="hook">{hook}</span><span class="more">{rest}</span></div>
</body></html>"""
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(page)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("store_dir", nargs="?")
    ap.add_argument("--icon")
    ap.add_argument("--thumbs", nargs="*", default=None)
    ap.add_argument("--title-text")
    ap.add_argument("--description")
    ap.add_argument("--preview")
    ap.add_argument("--strict", action="store_true", help="exit 1 on warnings too")
    args = ap.parse_args()

    icon_path, thumb_paths, title, description = args.icon, args.thumbs, args.title_text, None
    if args.store_dir:
        d = args.store_dir
        if not icon_path:
            found = sorted(glob.glob(os.path.join(d, "icon.*")))
            icon_path = found[0] if found else None
        if thumb_paths is None:
            thumb_paths = sorted(p for p in glob.glob(os.path.join(d, "thumbnails", "*")) if os.path.isfile(p))
        if title is None and os.path.exists(os.path.join(d, "title.txt")):
            title = open(os.path.join(d, "title.txt"), encoding="utf-8").read().strip()
        if not args.description and os.path.exists(os.path.join(d, "description.txt")):
            args.description = os.path.join(d, "description.txt")
    if args.description:
        description = open(args.description, encoding="utf-8").read()
    thumb_paths = thumb_paths or []

    report = Report()
    icon = check_icon(icon_path, report) if icon_path else None
    if not icon_path:
        report.warn("icon", "no icon given; the default generated icon kills click-through")
    if len(thumb_paths) > MAX_THUMBS:
        report.error("thumbnails", f"{len(thumb_paths)} thumbnails; the limit is {MAX_THUMBS} images/videos")
    thumbs = [check_thumbnail(p, report, i) for i, p in enumerate(thumb_paths)]
    if len(thumb_paths) < 2:
        report.warn("thumbnails", "thumbnail personalization needs 2-5 active Home page thumbnails")
    hashes = [(i, average_hash(t)) for i, t in enumerate(thumbs) if t is not None]
    group = {i: i for i, _ in hashes}

    def root(i):
        while group[i] != i:
            i = group[i]
        return i

    for a in range(len(hashes)):
        for b in range(a + 1, len(hashes)):
            if sum(x != y for x, y in zip(hashes[a][1], hashes[b][1])) <= 10:
                group[root(hashes[b][0])] = root(hashes[a][0])
    clusters = {}
    for i, _ in hashes:
        clusters.setdefault(root(i), []).append(i + 1)
    for members in clusters.values():
        if len(members) > 1:
            names = ", ".join(map(str, members[:-1])) + f" and {members[-1]}"
            report.warn("thumbnails", f"thumbnails {names} look almost the same; personalization learns nothing from near-duplicates")
    if title is not None:
        check_title(title, report)
    if description is not None:
        check_description(description, title, report)

    for level, where, message in report.items:
        print(f"{level:5} {where}: {message}")
    errors, warnings = report.count("ERROR"), report.count("WARN")
    print(f"\n{errors} error(s), {warnings} warning(s)")
    if args.preview:
        write_preview(args.preview, icon, thumbs, title, description, report)
        print(f"preview: {args.preview}")
    if errors or (args.strict and warnings):
        sys.exit(1)


if __name__ == "__main__":
    main()
