#!/usr/bin/env python3
"""Test helper: convert the task tables of a PRODUCTION_PLAN.md (Undead Eats format) into tasks.csv.

  python3 plan_to_csv.py PRODUCTION_PLAN.md tasks.csv

Rows are table lines whose first cell looks like SYS-01. The last cell is the dependency list when the
table has a 'Zależy od' column, the priority is the cell before it (or the last cell for 3-column tables).
Dependency text is normalised: '–' means none, 'UI-02..07' expands to UI-02..UI-07, 'wszystkie SYS'
means every SYS task. Priority maps to a milestone (MVP=M1, MVP/Launch and Launch=M3, Post=M4) and the
SYS/DATA/SEC prefixes live in files, everything else in Studio."""
import csv
import re
import sys

# MVP/Launch is a hybrid priority: the plan itself lands those tasks in M3 (soft launch), so it maps there
MILESTONE = {"MVP": "M1", "MVP/LAUNCH": "M3", "LAUNCH": "M3", "POST": "M4"}
FILE_PREFIXES = {"SYS", "DATA", "SEC"}


def main(src, dst):
    rows = []
    for line in open(src, encoding="utf-8"):
        if not re.match(r"^\|\s*[A-Z]+-\d+\s*\|", line):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 6:
            task, priority, deps = cells[1], cells[-2], cells[-1]
        else:
            task, priority, deps = cells[1], cells[-1], ""
        rows.append([cells[0], task, priority, deps])

    ids = [r[0] for r in rows]
    out = []
    for tid, task, priority, deps in rows:
        prefix = tid.split("-")[0]
        found = []
        if re.search(r"wszystkie\s+([A-Z]+)", deps):
            pre = re.search(r"wszystkie\s+([A-Z]+)", deps).group(1)
            found += [i for i in ids if i.startswith(pre + "-") and i != tid]
        for m in re.finditer(r"([A-Z]+)-(\d+)(?:\.\.(\d+))?", deps):
            lo = int(m.group(2))
            hi = int(m.group(3) or lo)
            found += [f"{m.group(1)}-{n:02d}" for n in range(lo, hi + 1)]
        found = [d for d in dict.fromkeys(found) if d in ids and d != tid]
        milestone = MILESTONE.get(priority.strip().upper().replace(" ", ""), "M3")
        out.append([tid, prefix, task, "", "", priority, milestone, ";".join(found),
                    "file" if prefix in FILE_PREFIXES else "studio", "todo"])

    with open(dst, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow("id,discipline,task,owner,size,priority,milestone,depends_on,surface,status".split(","))
        w.writerows(out)
    print(f"{len(out)} tasks")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
