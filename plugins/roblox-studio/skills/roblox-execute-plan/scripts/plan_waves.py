#!/usr/bin/env python3
"""Turn a production plan's tasks.csv into execution waves for one of three workflows.

  python3 plan_waves.py tasks.csv --workflow a|b|c [--json] [--next] [--milestone M1]

Workflows (what the creator picked in the roblox-execute-plan skill):
  a  Rojo and files   every task of a wave can run in parallel (separate git worktrees);
                      tasks of the same discipline are split into sub-waves because they
                      are likely to touch the same files
  b  Studio only      one agent at a time writes to Studio (studio_queue); tasks that do not
                      write to Studio (surface = file) can be prepared in parallel
  c  mixed            file lane runs in parallel, Studio lane is serial; a sync point is a
                      Studio task that needs the output of a pending file task

tasks.csv columns: id, milestone, depends_on (required); discipline, surface (file|studio) and
status (done tasks are skipped) are used when present. surface is required for workflow c.
depends_on separators: ; | , or whitespace. Milestones are M1, M2, ... (the number orders them).

Exit 0 on success, 1 with "ERROR: ..." lines on stderr when the plan is invalid.
Standard library only.
"""
import argparse
import csv
import json
import re
import sys


def parse_list(text):
    return [t for t in re.split(r"[;,|\s]+", (text or "").strip()) if t]


def milestone_num(text):
    m = re.search(r"\d+", text or "")
    return int(m.group()) if m else None


def load(path, workflow):
    errors = []
    try:
        with open(path, newline="", encoding="utf-8-sig") as f:
            reader = csv.DictReader(f)
            if reader.fieldnames is None:
                return None, ["ERROR: tasks.csv is empty"]
            reader.fieldnames = [h.strip().lower() for h in reader.fieldnames]
            cols = set(reader.fieldnames)
            rows = [{k: (v or "").strip() for k, v in r.items() if k} for r in reader]
    except OSError as e:
        return None, [f"ERROR: cannot read {path}: {e}"]

    for need in ("id", "milestone", "depends_on"):
        if need not in cols:
            errors.append(f"ERROR: tasks.csv has no '{need}' column")
    if workflow == "c" and "surface" not in cols:
        errors.append("ERROR: workflow c needs a 'surface' column (file or studio) in tasks.csv; "
                      "ask roblox-game-production-plan to add it")
    if errors:
        return None, errors

    tasks = {}
    for i, r in enumerate(rows, start=2):
        tid = r.get("id", "")
        if not tid:
            continue
        if tid in tasks:
            errors.append(f"ERROR: duplicate task id {tid} (line {i})")
            continue
        n = milestone_num(r.get("milestone", ""))
        if n is None:
            errors.append(f"ERROR: {tid}: milestone '{r.get('milestone', '')}' has no number (use M1, M2, ...)")
        surface = r.get("surface", "").lower()
        if surface not in ("", "file", "studio"):
            errors.append(f"ERROR: {tid}: surface '{surface}' must be 'file' or 'studio'")
        if workflow == "c" and surface == "":
            errors.append(f"ERROR: {tid}: workflow c needs a surface (file or studio)")
        tasks[tid] = {
            "id": tid,
            "discipline": r.get("discipline", "") or tid.split("-")[0],
            "surface": surface or "studio",
            "milestone": n,
            "deps": parse_list(r.get("depends_on", "")),
            "done": r.get("status", "").lower() == "done",
        }
    return tasks, errors


def validate(tasks):
    errors = []
    for t in tasks.values():
        for d in t["deps"]:
            if d not in tasks:
                errors.append(f"ERROR: {t['id']}: unknown dependency {d}")
            elif t["milestone"] is not None and tasks[d]["milestone"] is not None and tasks[d]["milestone"] > t["milestone"]:
                errors.append(f"ERROR: {t['id']} (M{t['milestone']}) depends on {d}, which is in a later milestone (M{tasks[d]['milestone']})")
    if errors:
        return errors
    # cycle detection (iterative DFS, reports the cycle path)
    state = {}
    for start in sorted(tasks):
        if state.get(start):
            continue
        stack = [(start, iter(sorted(tasks[start]["deps"])))]
        path = [start]
        state[start] = 1
        while stack:
            node, it = stack[-1]
            nxt = next(it, None)
            if nxt is None:
                state[node] = 2
                stack.pop()
                path.pop()
            elif state.get(nxt) == 1:
                cyc = path[path.index(nxt):] + [nxt]
                errors.append("ERROR: dependency cycle: " + " -> ".join(cyc))
                return errors
            elif not state.get(nxt):
                state[nxt] = 1
                path.append(nxt)
                stack.append((nxt, iter(sorted(tasks[nxt]["deps"]))))
    return errors


def levels(pending):
    """Wave index per pending task: 0 if no pending dependency in the same milestone, else 1 + max."""
    memo = {}

    def lvl(tid):
        if tid in memo:
            return memo[tid]
        t = pending[tid]
        ds = [d for d in t["deps"] if d in pending and pending[d]["milestone"] == t["milestone"]]
        memo[tid] = 0 if not ds else 1 + max(lvl(d) for d in ds)
        return memo[tid]

    for tid in pending:
        lvl(tid)
    return memo


def build(tasks, workflow):
    pending = {k: v for k, v in tasks.items() if not v["done"]}
    lv = levels(pending)
    warnings = []
    out = []
    for m in sorted({t["milestone"] for t in pending.values()}):
        ids = sorted(k for k, v in pending.items() if v["milestone"] == m)
        count = max(lv[i] for i in ids) + 1
        waves = []
        for w in range(count):
            wid = [i for i in ids if lv[i] == w]
            if workflow == "a":
                subs = []
                for i in wid:
                    for sub in subs:
                        if all(pending[j]["discipline"] != pending[i]["discipline"] for j in sub):
                            sub.append(i)
                            break
                    else:
                        subs.append([i])
                if len(subs) > 1:
                    split = sorted({d for d in (pending[i]["discipline"] for i in wid)
                                    if sum(pending[i]["discipline"] == d for i in wid) > 1})
                    for d in split:
                        same = [i for i in wid if pending[i]["discipline"] == d]
                        warnings.append(f"M{m} wave {w}: {', '.join(same)} are all {d} tasks and likely touch the same files; "
                                        f"run them in separate sub-waves (or merge one by one)")
                waves.append({"wave": w, "sub_waves": [sorted(s) for s in subs]})
            elif workflow == "b":
                waves.append({
                    "wave": w,
                    "prepare_parallel": [i for i in wid if pending[i]["surface"] != "studio"],
                    "studio_queue": [i for i in wid if pending[i]["surface"] == "studio"],
                })
            else:
                sync = []
                for i in wid:
                    if pending[i]["surface"] == "studio":
                        after = sorted(d for d in pending[i]["deps"] if d in pending and pending[d]["surface"] == "file")
                        if after:
                            sync.append({"task": i, "after": after})
                waves.append({
                    "wave": w,
                    "file_lane": [i for i in wid if pending[i]["surface"] == "file"],
                    "studio_lane": [i for i in wid if pending[i]["surface"] == "studio"],
                    "sync_points": sync,
                })
        out.append({"milestone": f"M{m}", "waves": waves})
    return out, warnings


def render(result, workflow):
    lines = []
    names = {"a": "Rojo and files", "b": "Studio only", "c": "mixed"}
    lines.append(f"Workflow {workflow.upper()} ({names[workflow]})")
    if not result["milestones"]:
        lines.append("Nothing left to do: every task is done.")
    for m in result["milestones"]:
        lines.append(f"\n{m['milestone']}")
        for w in m["waves"]:
            lines.append(f"  wave {w['wave']}")
            if workflow == "a":
                for n, sub in enumerate(w["sub_waves"]):
                    lines.append(f"    parallel group {n + 1}: {', '.join(sub)}")
            elif workflow == "b":
                lines.append(f"    prepare in parallel: {', '.join(w['prepare_parallel']) or '-'}")
                lines.append(f"    Studio queue (one writer, in order): {', '.join(w['studio_queue']) or '-'}")
            else:
                lines.append(f"    file lane (parallel): {', '.join(w['file_lane']) or '-'}")
                lines.append(f"    Studio lane (serial): {', '.join(w['studio_lane']) or '-'}")
                for s in w["sync_points"]:
                    lines.append(f"    sync point: {s['task']} waits for {', '.join(s['after'])} to be synced into Studio")
    for w in result["warnings"]:
        lines.append(f"\nWARNING: {w}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("tasks_csv")
    ap.add_argument("--workflow", required=True, choices=["a", "b", "c"])
    ap.add_argument("--json", action="store_true", help="print JSON instead of a table")
    ap.add_argument("--next", action="store_true", help="only the first wave of the first unfinished milestone")
    ap.add_argument("--milestone", help="only this milestone, e.g. M2")
    args = ap.parse_args()

    tasks, errors = load(args.tasks_csv, args.workflow)
    if tasks is not None and not errors:
        errors = validate(tasks)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    milestones, warnings = build(tasks, args.workflow)
    if args.milestone:
        want = milestone_num(args.milestone)
        milestones = [m for m in milestones if milestone_num(m["milestone"]) == want]
    if args.next and milestones:
        milestones = [{"milestone": milestones[0]["milestone"], "waves": milestones[0]["waves"][:1]}]
    result = {"workflow": args.workflow, "milestones": milestones, "warnings": warnings}
    print(json.dumps(result, indent=2) if args.json else render(result, args.workflow))
    return 0


if __name__ == "__main__":
    sys.exit(main())
