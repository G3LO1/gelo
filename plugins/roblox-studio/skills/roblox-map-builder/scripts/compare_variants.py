#!/usr/bin/env python3
"""Fair comparison of map variants (two passes, two builders, two models, before/after): every
variant must be built from the SAME reference, captured with the SAME camera (one walkthrough scene,
e.g. from slice_check.luau --scene, played by roblox-launch-kit's ShotDirector) and scored on the SAME
criteria. Otherwise the comparison says nothing.

  compare_variants.py compare.json [--html compare.html]

compare.json (paths relative to it):
{
  "name": "SpiceHall",
  "reference": "ref/spice-hall.png",          the concept every variant was built from
  "scene": "SliceWalk.json",                  the walkthrough scene the shots were taken with
  "criteria": ["Matches the reference", "Readable route", "Interior", "Scale at eye height", "Performance"],
  "variants": [
    { "name": "Pass1", "reference": "ref/spice-hall.png", "scene": "SliceWalk.json", "shots": "shots/pass1",
      "slice": "pass", "cost": "medium effort, 40 min", "scores": { "Matches the reference": 3, ... },
      "notes": "kit snapped together, flat walls" }
  ]
}
Shots: <shots folder>/<shot name>.png|.jpg for every shot in the scene (Entrance, Route, Interior,
Scale for a slice walkthrough). Scores 1-5. Errors (exit 1): a variant built from another reference
or captured with another scene, a missing shot, a missing or out-of-range score, an unknown criterion.
Warnings: shots of one view at different sizes, a variant whose slice check didn't pass.
"""

import argparse
import base64
import hashlib
import html
import io
import json
import os
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: pip install pillow")

EXTENSIONS = (".png", ".jpg", ".jpeg")


def digest(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def find_shot(folder, name):
    for ext in EXTENSIONS:
        path = os.path.join(folder, name + ext)
        if os.path.exists(path):
            return path
    return None


def thumb(path, width=360):
    image = Image.open(path).convert("RGB")
    image.thumbnail((width, width * 4))
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=85)
    return "data:image/jpeg;base64," + base64.b64encode(buffer.getvalue()).decode()


def compare(path):
    base = os.path.dirname(os.path.abspath(path))
    spec = json.load(open(path, encoding="utf-8"))
    lines = []

    def add(level, where, message):
        lines.append((level, where, message))

    def resolve(p):
        return os.path.normpath(os.path.join(base, p)) if p else None

    reference = resolve(spec.get("reference"))
    scene_path = resolve(spec.get("scene"))
    if not reference or not os.path.exists(reference):
        add("ERROR", "compare", "no reference image: every variant must be judged against the same concept")
        return lines, None
    if not scene_path or not os.path.exists(scene_path):
        add("ERROR", "compare", "no walkthrough scene: every variant must be captured with the same camera")
        return lines, None
    ref_hash, scene_hash = digest(reference), digest(scene_path)
    scene = json.load(open(scene_path, encoding="utf-8"))
    shots = [s["name"] for s in scene.get("shots") or []]
    if not shots:
        add("ERROR", "compare", f"the scene {os.path.basename(scene_path)} has no shots to compare")
    criteria = spec.get("criteria") or []
    if not criteria:
        add("ERROR", "compare", "no criteria: decide what 'better' means before looking")
    variants = spec.get("variants") or []
    if len(variants) < 2:
        add("ERROR", "compare", "a comparison needs at least 2 variants")

    table = {"reference": reference, "shots": shots, "criteria": criteria, "variants": []}
    sizes = {}
    for variant in variants:
        name = variant.get("name", "?")
        row = {"name": name, "shots": {}, "scores": {}, "cost": variant.get("cost", ""), "notes": variant.get("notes", ""), "slice": variant.get("slice")}
        v_ref = resolve(variant.get("reference"))
        if not v_ref or not os.path.exists(v_ref):
            add("ERROR", name, "no reference given: which concept was it built from?")
        elif digest(v_ref) != ref_hash:
            add("ERROR", name, f"built from another reference ({os.path.basename(v_ref)}): not comparable with the others")
        v_scene = resolve(variant.get("scene"))
        if not v_scene or not os.path.exists(v_scene):
            add("ERROR", name, "no scene given: which camera took the shots?")
        elif digest(v_scene) != scene_hash:
            add("ERROR", name, f"shots taken with another scene ({os.path.basename(v_scene)}): different camera, not comparable")
        folder = resolve(variant.get("shots")) or ""
        for shot in shots:
            found = find_shot(folder, shot)
            if not found:
                add("ERROR", name, f"missing shot {shot} in {variant.get('shots')}")
                continue
            row["shots"][shot] = found
            with Image.open(found) as image:
                sizes.setdefault(shot, {})[name] = image.size
        scores = variant.get("scores") or {}
        for criterion in scores:
            if criterion not in criteria:
                add("ERROR", name, f"score for unknown criterion '{criterion}'")
        for criterion in criteria:
            value = scores.get(criterion)
            if not isinstance(value, int) or isinstance(value, bool) or not 1 <= value <= 5:
                add("ERROR", name, f"'{criterion}' needs a score from 1 to 5")
            else:
                row["scores"][criterion] = value
        if variant.get("slice") not in (None, "pass"):
            add("WARN", name, f"slice check: {variant.get('slice')} (accept the slice before comparing looks)")
        table["variants"].append(row)
    for shot, by_variant in sizes.items():
        if len(set(by_variant.values())) > 1:
            listed = ", ".join(f"{v} {w}x{h}" for v, (w, h) in sorted(by_variant.items()))
            add("WARN", shot, f"shots at different sizes ({listed}): capture at one resolution")
    return lines, table


def write_html(path, spec_name, table, lines):
    shots, variants = table["shots"], table["variants"]
    head = "".join(f"<th>{html.escape(v['name'])}</th>" for v in variants)
    rows = ""
    for shot in shots:
        cells = "".join(
            f"<td><img src='{thumb(v['shots'][shot])}' alt='{html.escape(v['name'])} {html.escape(shot)}'></td>" if shot in v["shots"] else "<td class='missing'>missing</td>"
            for v in variants
        )
        rows += f"<tr><th scope='row'>{html.escape(shot)}</th><td><img src='{thumb(table['reference'])}' alt='reference'></td>{cells}</tr>"
    score_rows = ""
    for criterion in table["criteria"]:
        score_rows += f"<tr><th scope='row'>{html.escape(criterion)}</th>" + "".join(f"<td>{v['scores'].get(criterion, '-')}</td>" for v in variants) + "</tr>"
    totals = "".join(f"<td><b>{sum(v['scores'].values())}</b></td>" for v in variants)
    meta = ""
    for key, label in (("slice", "Slice check"), ("cost", "Cost / effort"), ("notes", "Notes")):
        meta += f"<tr><th scope='row'>{label}</th>" + "".join(f"<td>{html.escape(str(v.get(key) or ''))}</td>" for v in variants) + "</tr>"
    problems = "".join(f"<li class='{l.lower()}'><b>{l}</b> {html.escape(w)}: {html.escape(m)}</li>" for l, w, m in lines) or "<li>Same reference, same camera, same criteria: comparable.</li>"
    page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Variant comparison</title><style>
body{{font:14px/1.45 system-ui,sans-serif;margin:0;padding:16px;background:#f3f4f6;color:#16181d}}
h1{{font-size:20px}} h2{{font-size:16px;margin-top:24px}} .scroll{{overflow-x:auto}}
table{{border-collapse:collapse;background:#fff;border-radius:8px}} th,td{{padding:8px;border-bottom:1px solid #e5e7eb;text-align:left;vertical-align:top}}
td img{{width:240px;height:auto;display:block;border-radius:6px}} .missing{{color:#b3261e}}
li.error b{{color:#b3261e}} li.warn b{{color:#8a5a00}}
</style></head><body>
<h1>{html.escape(spec_name)}: variants from one reference, one camera, one set of criteria</h1>
<ul>{problems}</ul>
<h2>Same views, side by side</h2><div class="scroll"><table><tr><th>View</th><th>Reference</th>{head}</tr>{rows}</table></div>
<h2>Scores (1-5)</h2><div class="scroll"><table><tr><th>Criterion</th>{head}</tr>{score_rows}<tr><th scope='row'>Total</th>{totals}</tr>{meta}</table></div>
</body></html>"""
    with open(path, "w", encoding="utf-8") as f:
        f.write(page)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("compare")
    ap.add_argument("--html")
    args = ap.parse_args()
    lines, table = compare(args.compare)
    for level, where, message in lines:
        print(f"{level:5} {where}: {message}")
    if table:
        for v in table["variants"]:
            print(f"      {v['name']}: total {sum(v['scores'].values())} over {len(v['scores'])} criteria, {len(v['shots'])}/{len(table['shots'])} shots")
        if args.html:
            write_html(args.html, json.load(open(args.compare, encoding="utf-8")).get("name", "Comparison"), table, lines)
            print(f"wrote {args.html}")
    errors = sum(1 for l in lines if l[0] == "ERROR")
    print(f"{errors} error(s), {sum(1 for l in lines if l[0] == 'WARN')} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
