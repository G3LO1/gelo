#!/usr/bin/env python3
"""YouTube research for improving the plugin's skills: find tutorials and pull their full transcripts.

  python3 tools/yt_research.py search "roblox studio realistic lighting" -n 15 [--after 2024-01-01] [--json]
  python3 tools/yt_research.py transcript VIDEO_ID_OR_URL [...] [-o DIR] [--lang en] [--every 30] [--sleep 3]
  python3 tools/yt_research.py parse-vtt FILE.vtt [--every 30]     # offline, used by the tests

`search` lists id, upload date, duration, views, channel and title (newest metadata needs one request per video,
so --after/--details are slower). `transcript` writes one Markdown file per video: header (title, channel, date,
duration, views, URL), the description's chapter list, then the cleaned transcript as paragraphs stamped
[mm:ss] every --every seconds, with deep links. Uses manual subtitles when the video has them, else YouTube's
auto captions. Needs: pip install yt-dlp. Videos without any captions are reported and skipped. From cloud IPs
YouTube sometimes answers "Sign in to confirm you're not a bot": transcript retries with back-off, search just
marks that row; wait a minute and rerun, keep batches small.

Transcripts are raw research material: verify every claim against current Roblox docs/Studio before it goes into
a skill, record the source URL, and never copy a tutorial's text or assets wholesale.
"""
import argparse
import html
import json
import re
import sys
import tempfile
import time
from pathlib import Path

TS = re.compile(r"(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{3})\s+-->\s+(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{3})")
TAG = re.compile(r"<[^>]+>")


def _secs(h, m, s, ms):
    return int(h or 0) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


def fmt_time(t):
    t = int(t)
    h, rem = divmod(t, 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"


def parse_vtt(text):
    """Return [(start_seconds, line)] with YouTube's rolling-caption duplication removed.

    Auto captions repeat every line: each cue shows the previous line again plus the new one (with <c> word
    timing tags). We keep each distinct line once, at the time it first appeared."""
    cues = []
    start = None
    for raw in text.splitlines():
        line = raw.strip()
        m = TS.search(line)
        if m:
            start = _secs(*m.groups()[:4])
            continue
        if start is None or not line or line.startswith(("WEBVTT", "Kind:", "Language:", "NOTE", "STYLE")):
            continue
        clean = html.unescape(TAG.sub("", line)).strip()
        clean = re.sub(r"\s+", " ", clean)
        if clean:
            cues.append((start, clean))
    out = []
    recent = []  # last few lines; rolling captions only ever repeat the immediately preceding ones
    for t, line in cues:
        if line in recent:
            continue
        out.append((t, line))
        recent = (recent + [line])[-3:]
    return out


def paragraphs(lines, every=30):
    """Group lines into paragraphs of ~`every` seconds: [(start_seconds, text)]."""
    paras = []
    for t, line in lines:
        if not paras or t - paras[-1][0] >= every:
            paras.append([t, line])
        else:
            paras[-1][1] += " " + line
    return [(t, re.sub(r"\s+", " ", s).strip()) for t, s in paras]


def _ydl(extra=None):
    try:
        import yt_dlp
    except ImportError:
        sys.exit("yt-dlp is not installed: pip install yt-dlp")
    opts = {"quiet": True, "no_warnings": True, "noprogress": True, "skip_download": True, "socket_timeout": 30,
            "retries": 2, "extractor_retries": 1}
    opts.update(extra or {})
    return yt_dlp.YoutubeDL(opts)


def video_id(s):
    m = re.search(r"(?:v=|youtu\.be/|shorts/|embed/)([\w-]{11})", s)
    return m.group(1) if m else s


def cmd_search(a):
    detailed = a.details or a.after
    with _ydl({"extract_flat": "in_playlist"}) as y:
        res = y.extract_info(f"ytsearch{a.n}:{a.query}", download=False)
    rows = []
    for e in res.get("entries") or []:
        if not e:
            continue
        row = {k: e.get(k) for k in ("id", "title", "channel", "duration", "view_count", "upload_date")}
        row["channel"] = row["channel"] or e.get("uploader")
        if detailed and not row["upload_date"]:
            try:
                with _ydl() as y:
                    full = y.extract_info(f"https://www.youtube.com/watch?v={row['id']}", download=False)
                for k in ("upload_date", "view_count", "duration", "channel"):
                    row[k] = full.get(k) or row[k]
            except Exception as ex:  # one broken video must not kill the search
                row["error"] = str(ex)[:120]
        rows.append(row)
    if a.after:
        cut = a.after.replace("-", "")
        rows = [r for r in rows if (r.get("upload_date") or "0") >= cut]
    if a.json:
        print(json.dumps(rows, indent=1, ensure_ascii=False))
        return
    for r in rows:
        d = r.get("upload_date") or "?"
        d = f"{d[:4]}-{d[4:6]}-{d[6:]}" if len(d) == 8 else d
        dur = fmt_time(r["duration"]) if r.get("duration") else "?"
        views = f"{r['view_count']:,}" if r.get("view_count") else "?"
        print(f"{r['id']}  {d}  {dur:>8}  {views:>11} views  {r.get('channel') or '?'}  |  {r.get('title')}")


def _chapters(info):
    ch = info.get("chapters") or []
    return [(c.get("start_time", 0), c.get("title", "")) for c in ch]


def render_markdown(info, lines, every):
    vid = info.get("id", "")
    url = f"https://www.youtube.com/watch?v={vid}"
    d = info.get("upload_date") or ""
    d = f"{d[:4]}-{d[4:6]}-{d[6:]}" if len(d) == 8 else "?"
    out = [
        f"# {info.get('title', vid)}",
        "",
        f"- URL: {url}",
        f"- Channel: {info.get('channel') or info.get('uploader') or '?'}",
        f"- Uploaded: {d}",
        f"- Duration: {fmt_time(info['duration']) if info.get('duration') else '?'}",
        f"- Views: {info['view_count']:,}" if info.get("view_count") else "- Views: ?",
        f"- Captions: {info.get('_caption_kind', '?')}",
        "",
    ]
    chs = _chapters(info)
    if chs:
        out += ["## Chapters", ""] + [f"- [{fmt_time(t)}]({url}&t={int(t)}s) {title}" for t, title in chs] + [""]
    out += ["## Transcript", ""]
    for t, text in paragraphs(lines, every):
        out += [f"[{fmt_time(t)}]({url}&t={int(t)}s) {text}", ""]
    return "\n".join(out)


def fetch_transcript(target, lang, every):
    vid = video_id(target)
    url = f"https://www.youtube.com/watch?v={vid}"
    with tempfile.TemporaryDirectory() as tmp:
        opts = {
            "writesubtitles": True,
            "writeautomaticsub": True,
            "subtitleslangs": [lang, f"{lang}-orig", f"{lang}.*"],
            "subtitlesformat": "vtt",
            "outtmpl": str(Path(tmp) / "%(id)s.%(ext)s"),
        }
        with _ydl(opts) as y:
            info = y.extract_info(url, download=True)
        files = sorted(Path(tmp).glob(f"{vid}*.vtt"))
        if not files:
            return info, None
        manual = set((info.get("subtitles") or {}).keys())
        tracks = []
        for f in files:
            parsed = parse_vtt(f.read_text(encoding="utf-8", errors="replace"))
            words = sum(len(t.split()) for _, t in parsed)
            tracks.append((f.name.split(".")[-2] in manual, words, parsed))
        lines = choose_track(tracks)
        info["_caption_kind"] = next(("manual" if m else "auto-generated") for m, _, p in tracks if p is lines)
    return info, lines


def choose_track(tracks):
    """tracks = [(is_manual, word_count, lines)]. Prefer manual captions unless they are a stub (some uploads have
    a 'manual' track that is just a title card) - then the fuller auto track wins."""
    if not tracks:
        return None
    best_auto = max((t for t in tracks if not t[0]), key=lambda t: t[1], default=None)
    best_manual = max((t for t in tracks if t[0]), key=lambda t: t[1], default=None)
    if best_manual and (not best_auto or best_manual[1] >= 0.5 * best_auto[1]):
        return best_manual[2]
    return best_auto[2]


def slug(s, n=60):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:n] or "video"


def cmd_transcript(a):
    outdir = Path(a.o) if a.o else None
    if outdir:
        outdir.mkdir(parents=True, exist_ok=True)
    status = 0
    blocked = 0
    for i, target in enumerate(a.videos):
        vid = video_id(target)
        if outdir and any(outdir.glob(f"{vid}-*.md")):
            print(f"have {vid} (already in {outdir})")
            continue
        if blocked >= 2:  # YouTube is rate-limiting this IP; more requests only extend the block
            print(f"SKIP {target}: not tried, rate-limited; rerun later (finished files are kept)", file=sys.stderr)
            status = 1
            continue
        if i and a.sleep:
            time.sleep(a.sleep)  # spacing requests keeps YouTube's "confirm you're not a bot" check away
        info = lines = None
        for attempt in range(3):
            try:
                info, lines = fetch_transcript(target, a.lang, a.every)
                break
            except Exception as ex:
                err = str(ex).splitlines()[0][:200]
                limited = "not a bot" in err or "429" in err
                if not limited or attempt == 2:
                    print(f"SKIP {target}: {err}", file=sys.stderr)
                    blocked += limited
                    break
                time.sleep(30 * (attempt + 1))
        if info is None:
            status = 1
            continue
        blocked = 0
        if not lines:
            print(f"SKIP {target}: no '{a.lang}' captions", file=sys.stderr)
            status = 1
            continue
        md = render_markdown(info, lines, a.every)
        if outdir:
            p = outdir / f"{info['id']}-{slug(info.get('title', ''))}.md"
            p.write_text(md, encoding="utf-8")
            words = sum(len(t.split()) for _, t in lines)
            print(f"{p}  ({words} words, {info.get('_caption_kind')})")
        else:
            print(md)
    return status


def cmd_parse_vtt(a):
    lines = parse_vtt(Path(a.file).read_text(encoding="utf-8"))
    for t, text in paragraphs(lines, a.every):
        print(f"[{fmt_time(t)}] {text}")


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("search", help="search YouTube")
    s.add_argument("query")
    s.add_argument("-n", type=int, default=10, help="number of results (default 10)")
    s.add_argument("--after", help="only videos uploaded on/after YYYY-MM-DD (fetches details per video)")
    s.add_argument("--details", action="store_true", help="fetch upload date/views per video")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_search)
    t = sub.add_parser("transcript", help="download cleaned transcripts as Markdown")
    t.add_argument("videos", nargs="+", help="video ids or URLs")
    t.add_argument("-o", help="output directory (default: print to stdout)")
    t.add_argument("--lang", default="en")
    t.add_argument("--every", type=int, default=30, help="seconds per timestamped paragraph (default 30)")
    t.add_argument("--sleep", type=float, default=3, help="seconds between videos (default 3)")
    t.set_defaults(fn=cmd_transcript)
    v = sub.add_parser("parse-vtt", help="clean a local .vtt file (offline)")
    v.add_argument("file")
    v.add_argument("--every", type=int, default=30)
    v.set_defaults(fn=cmd_parse_vtt)
    # Video ids may start with "-" (e.g. -DoOf32pkPo); argparse would read them as options, so pass them as URLs.
    argv = [f"https://www.youtube.com/watch?v={x}" if re.fullmatch(r"-[\w-]{10}", x) else x
            for x in (sys.argv[1:] if argv is None else argv)]
    a = p.parse_args(argv)
    return a.fn(a) or 0


if __name__ == "__main__":
    sys.exit(main())
