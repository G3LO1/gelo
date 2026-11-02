"""Offline tests for tools/yt_research.py (no network, yt-dlp not needed).
Run from the repo root: python3 tests/yt-research/test_yt_research.py"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import yt_research as yt  # noqa: E402

HERE = Path(__file__).parent
fails = 0


def check(name, cond, detail=""):
    global fails
    print(("  ok   " if cond else "  FAIL ") + name + ("" if cond else f": {detail}"))
    fails += 0 if cond else 1


lines = yt.parse_vtt((HERE / "rolling.vtt").read_text())
texts = [t for _, t in lines]
check("rolling captions deduplicated", texts == ["First set the lighting", "style to realistic & check",
                                                 "then add bloom", "an hour later"], texts)
check("word timing tags and entities removed", not any("<" in t or "&amp;" in t for t in texts), texts)
check("first-appearance timestamps", [round(t) for t, _ in lines] == [0, 2, 31, 3723], lines)

paras = yt.paragraphs(lines, every=30)
check("paragraphs grouped by 30 s", len(paras) == 3 and paras[0][1] == "First set the lighting style to realistic & check",
      paras)
check("time format", (yt.fmt_time(75), yt.fmt_time(3723)) == ("01:15", "1:02:03"))

for s in ("https://www.youtube.com/watch?v=adgCWET34rU&t=10s", "https://youtu.be/adgCWET34rU",
          "https://www.youtube.com/shorts/adgCWET34rU", "adgCWET34rU"):
    check(f"video id from {s}", yt.video_id(s) == "adgCWET34rU", yt.video_id(s))

stub, full = [(0, "Title card")], [(0, "word " * 50)]
check("stub manual track loses to auto", yt.choose_track([(True, 2, stub), (False, 50, full)]) is full)
check("real manual track wins", yt.choose_track([(True, 40, stub), (False, 50, full)]) is stub)
check("auto only", yt.choose_track([(False, 50, full)]) is full)
check("no tracks", yt.choose_track([]) is None)

info = {"id": "adgCWET34rU", "title": "T", "channel": "C", "upload_date": "20260627", "duration": 318,
        "view_count": 71037, "_caption_kind": "auto-generated", "chapters": [{"start_time": 42, "title": "Sky"}]}
md = yt.render_markdown(info, lines, 30)
check("markdown header", "- Uploaded: 2026-06-27" in md and "- Views: 71,037" in md and "- Duration: 05:18" in md, md)
check("chapters deep-linked", "- [00:42](https://www.youtube.com/watch?v=adgCWET34rU&t=42s) Sky" in md, md)
check("transcript deep-linked", "[00:31](https://www.youtube.com/watch?v=adgCWET34rU&t=31s) then add bloom" in md, md)

out = subprocess.run([sys.executable, str(ROOT / "tools/yt_research.py"), "parse-vtt", str(HERE / "rolling.vtt")],
                     capture_output=True, text=True)
check("parse-vtt CLI", out.returncode == 0 and out.stdout.startswith("[00:00] First set the lighting"), out)

out = subprocess.run([sys.executable, str(ROOT / "tools/yt_research.py"), "transcript", "--help", "-DoOf32pkPo"],
                     capture_output=True, text=True)
check("id starting with '-' is not parsed as an option", out.returncode == 0, out.stderr)

print("all passed" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
