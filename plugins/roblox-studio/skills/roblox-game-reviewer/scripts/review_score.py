#!/usr/bin/env python3
"""Validates a game review, does the scoring math and renders the report.

Usage:
  review_score.py review.json [--previous old-review.json] [--json out.json] [--strict]

review.json:
  {
    "game": "Undead Eats",
    "date": "2026-11-03",                 # optional
    "build": "v0.4 playtest",             # optional
    "scores": {                           # every criterion below, score 1-5 + evidence
      "core_loop":   {"score": 4, "evidence": "Cook -> serve -> upgrade loop is clear within 30 s (playtest, 3 runs)"},
      ...
    },
    "blockers": [                         # optional: things that must be fixed before shipping
      {"title": "Currency can be granted by the client", "criterion": "stability",
       "evidence": "scan_luau.py SEC-001 in Shop.server.luau:42"}
    ],
    "strengths": ["..."],                 # optional
    "improvements": [                     # the backlog, sorted by this script
      {"title": "...", "criterion": "onboarding", "impact": 4, "effort": 2, "why": "..."}
    ]
  }

Points = weight x score / 5; the total is out of 100. Blockers cap the verdict at NEEDS WORK.
Errors (exit 1): missing/invalid criteria, scores outside 1-5, empty evidence, unknown criterion
names, a criterion scored 1-2 without any improvement for it. Warnings (exit 1 with --strict):
all scores identical, a 5 whose evidence is very short, improvements without a reason.
"""

import argparse
import json
import sys

# key -> (label, weight)
CRITERIA = {
    "core_loop": ("Core loop & fun", 20),
    "onboarding": ("First 60 seconds & onboarding", 12),
    "progression": ("Progression & retention", 16),
    "ux_mobile": ("UI/UX & mobile", 12),
    "polish": ("Polish: visuals, audio, game feel", 10),
    "content": ("Content & live-ops runway", 8),
    "monetization": ("Monetization health", 8),
    "stability": ("Stability, security & performance", 14),
}
assert sum(w for _, w in CRITERIA.values()) == 100

# (minimum total, verdict)
VERDICTS = [
    (80, "SHIP-READY"),
    (65, "SOLID"),
    (45, "NEEDS WORK"),
    (0, "BROKEN"),
]
BLOCKER_CAP = "NEEDS WORK"
SHORT_EVIDENCE = 25


def verdict_for(total, has_blockers):
    name = next(v for floor, v in VERDICTS if total >= floor)
    if has_blockers and [v for _, v in VERDICTS].index(name) < [v for _, v in VERDICTS].index(BLOCKER_CAP):
        return BLOCKER_CAP
    return name


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        sys.exit(f"cannot read {path}: {e}")


def is_score(value):
    return isinstance(value, int) and not isinstance(value, bool) and 1 <= value <= 5


def validate(review):
    errors, warns = [], []
    scores = review.get("scores")
    if not isinstance(scores, dict):
        return ["scores: missing object"], warns
    for key in CRITERIA:
        entry = scores.get(key)
        if entry is None:
            errors.append(f"scores.{key}: missing")
            continue
        if not isinstance(entry, dict) or not is_score(entry.get("score")):
            errors.append(f"scores.{key}: 'score' must be an integer 1-5")
            continue
        evidence = str(entry.get("evidence", "")).strip()
        if not evidence:
            errors.append(f"scores.{key}: 'evidence' is required (what you saw, measured or read)")
        elif entry["score"] == 5 and len(evidence) < SHORT_EVIDENCE:
            warns.append(f"scores.{key}: a 5 needs more than a few words of evidence")
    for key in scores:
        if key not in CRITERIA:
            errors.append(f"scores.{key}: unknown criterion (valid: {', '.join(CRITERIA)})")

    blockers = review.get("blockers", [])
    for i, b in enumerate(blockers):
        if not isinstance(b, dict) or not str(b.get("title", "")).strip():
            errors.append(f"blockers[{i}]: needs a 'title'")
        elif b.get("criterion") not in CRITERIA:
            errors.append(f"blockers[{i}]: 'criterion' must be one of {', '.join(CRITERIA)}")

    improvements = review.get("improvements", [])
    covered = set()
    for i, imp in enumerate(improvements):
        where = f"improvements[{i}]"
        if not isinstance(imp, dict) or not str(imp.get("title", "")).strip():
            errors.append(f"{where}: needs a 'title'")
            continue
        if imp.get("criterion") not in CRITERIA:
            errors.append(f"{where}: 'criterion' must be one of {', '.join(CRITERIA)}")
        else:
            covered.add(imp["criterion"])
        for field in ("impact", "effort"):
            if not is_score(imp.get(field)):
                errors.append(f"{where}: '{field}' must be an integer 1-5")
        if not str(imp.get("why", "")).strip():
            warns.append(f"{where}: add a 'why' (the problem it fixes)")
    for b in blockers:
        if isinstance(b, dict) and b.get("criterion") in CRITERIA:
            covered.add(b["criterion"])
    for key, (label, _) in CRITERIA.items():
        entry = scores.get(key)
        if isinstance(entry, dict) and is_score(entry.get("score")) and entry["score"] <= 2 and key not in covered:
            errors.append(f"scores.{key}: scored {entry['score']} ({label}) but no improvement or blocker targets it")
    if isinstance(scores, dict) and all(isinstance(scores.get(k), dict) for k in CRITERIA):
        values = {scores[k].get("score") for k in CRITERIA}
        if len(values) == 1:
            warns.append("every criterion has the same score; real games have a weakest and a strongest area")
    return errors, warns


def compute(review):
    rows, total = [], 0.0
    for key, (label, weight) in CRITERIA.items():
        entry = review["scores"][key]
        points = weight * entry["score"] / 5
        total += points
        rows.append({"key": key, "label": label, "weight": weight, "score": entry["score"],
                     "points": round(points, 1), "evidence": entry["evidence"].strip()})
    total = round(total, 1)
    blockers = review.get("blockers", [])
    improvements = []
    for imp in review.get("improvements", []):
        ratio = imp["impact"] / imp["effort"]
        weight = CRITERIA[imp["criterion"]][1]
        improvements.append({**imp, "ratio": round(ratio, 2), "weight": weight})
    # best value first: impact per effort, then impact, then the criterion's weight
    improvements.sort(key=lambda i: (-i["ratio"], -i["impact"], -i["weight"], i["title"]))
    for rank, imp in enumerate(improvements, 1):
        imp["rank"] = rank
        imp["tier"] = "Do now" if imp["ratio"] >= 2 or imp["impact"] == 5 else ("Next" if imp["ratio"] >= 1 else "Later")
    return {
        "game": review.get("game", "(unnamed game)"),
        "date": review.get("date", ""),
        "build": review.get("build", ""),
        "rows": rows,
        "total": total,
        "blockers": blockers,
        "verdict": verdict_for(total, bool(blockers)),
        "uncapped_verdict": verdict_for(total, False),
        "strengths": review.get("strengths", []),
        "improvements": improvements,
    }


def render(result, previous=None):
    out = []
    v = result["verdict"]
    head = f"# {result['game']}: {v} ({result['total']:g}/100)"
    out.append(head)
    meta = " | ".join(x for x in (result["date"], result["build"]) if x)
    if meta:
        out.append(meta)
    if result["blockers"] and v != result["uncapped_verdict"]:
        out.append(f"\nScore alone would be {result['uncapped_verdict']}; capped to {v} by {len(result['blockers'])} blocker(s).")
    out.append("")
    out.append("## Scorecard")
    prev_by_key = {r["key"]: r for r in previous["rows"]} if previous else {}
    cols = "| Criterion | Weight | Score (1-5) | Points |" + (" Change |" if previous else "") + " Evidence |"
    out.append(cols)
    out.append("| --- | --- | --- | --- |" + (" --- |" if previous else "") + " --- |")
    for r in result["rows"]:
        delta = ""
        if previous:
            d = round(r["points"] - prev_by_key[r["key"]]["points"], 1)
            delta = f" {d:+g} |"
        out.append(f"| {r['label']} | {r['weight']} | {r['score']} | {r['points']:g} |{delta} {r['evidence']} |")
    total_row = f"| **Total** | 100 | | **{result['total']:g}** |"
    if previous:
        total_row += f" **{round(result['total'] - previous['total'], 1):+g}** |"
    out.append(total_row + " |")
    out.append("")
    if previous:
        out.append(f"Compared with the previous review: {previous['total']:g} -> {result['total']:g} "
                   f"({previous['verdict']} -> {result['verdict']}).")
        out.append("")
    if result["blockers"]:
        out.append("## Blockers (fix before shipping)")
        for b in result["blockers"]:
            ev = f" Evidence: {b['evidence']}" if b.get("evidence") else ""
            out.append(f"- **{b['title']}** ({CRITERIA[b['criterion']][0]}).{ev}")
        out.append("")
    if result["strengths"]:
        out.append("## What works")
        out.extend(f"- {s}" for s in result["strengths"])
        out.append("")
    if result["improvements"]:
        out.append("## What to improve (best value first)")
        out.append("| # | Tier | Improvement | Area | Impact | Effort | Why |")
        out.append("| --- | --- | --- | --- | --- | --- | --- |")
        for i in result["improvements"]:
            out.append(f"| {i['rank']} | {i['tier']} | {i['title']} | {CRITERIA[i['criterion']][0]} | "
                       f"{i['impact']} | {i['effort']} | {i.get('why', '')} |")
        out.append("")
        out.append("Ranked by impact / effort. Do now = ratio of 2+ or impact 5; Next = 1-2; Later = under 1.")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("review")
    ap.add_argument("--previous", help="an earlier review.json (or --json output) to show the change against")
    ap.add_argument("--json", help="write the computed result to this file")
    ap.add_argument("--strict", action="store_true", help="exit 1 on warnings too")
    args = ap.parse_args()

    review = load(args.review)
    errors, warns = validate(review)
    for e in errors:
        print(f"ERROR {e}", file=sys.stderr)
    for w in warns:
        print(f"WARN  {w}", file=sys.stderr)
    if errors:
        return 1

    result = compute(review)
    previous = None
    if args.previous:
        prev_review = load(args.previous)
        if "rows" in prev_review:  # a --json output
            previous = prev_review
        else:
            perrs, _ = validate(prev_review)
            if perrs:
                for e in perrs:
                    print(f"ERROR previous: {e}", file=sys.stderr)
                return 1
            previous = compute(prev_review)
    print(render(result, previous))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
    return 1 if (warns and args.strict) else 0


if __name__ == "__main__":
    sys.exit(main())
