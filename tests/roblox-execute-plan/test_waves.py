#!/usr/bin/env python3
"""Tests for roblox-execute-plan/scripts/plan_waves.py. Run from the repo root:
python3 tests/roblox-execute-plan/test_waves.py"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "plugins/roblox-studio/skills/roblox-execute-plan/scripts/plan_waves.py"
FIX = Path(__file__).resolve().parent / "fixtures"

passed = failed = 0


def ok(msg):
    global passed
    passed += 1
    print(f"  ok   {msg}")


def bad(msg, extra=""):
    global failed
    failed += 1
    print(f"  FAIL {msg}")
    if extra:
        print("       " + str(extra).replace("\n", "\n       "))


def check(cond, msg, extra=""):
    ok(msg) if cond else bad(msg, extra)


def run(csv, *args):
    p = subprocess.run([sys.executable, "-I", str(SCRIPT), str(csv), *args], capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def waves(csv, wf, *extra):
    code, out, err = run(csv, "--workflow", wf, "--json", *extra)
    if code != 0:
        bad(f"{csv.name} workflow {wf} exits 0", err)
        return None
    return json.loads(out)


def by_milestone(data):
    return {m["milestone"]: m["waves"] for m in data["milestones"]}


print("workflow A (Rojo and files)")
d = waves(FIX / "good.csv", "a")
m = by_milestone(d)
check(m["M1"][0]["sub_waves"] == [["MAP-01", "SYS-01", "UI-01"]], "M1 wave 0: independent disciplines run together", m["M1"][0])
check(m["M1"][1]["sub_waves"] == [["MAP-02", "SYS-02"], ["SYS-03"]], "M1 wave 1: same discipline split into sub-waves", m["M1"][1])
check(m["M1"][2]["sub_waves"] == [["UI-02"]], "M1 wave 2: UI-02 waits for SYS-02", m["M1"][2])
check(m["M2"][0]["sub_waves"] == [["DATA-01", "MOD-01", "SYS-04"]], "M2 starts once M1 is done", m["M2"][0])
check(any("SYS-02" in w and "SYS-03" in w for w in d["warnings"]), "warning names the tasks that may touch the same files", d["warnings"])

print("workflow B (Studio only)")
d = waves(FIX / "good.csv", "b")
m = by_milestone(d)
check(m["M1"][0]["studio_queue"] == ["MAP-01"] and m["M1"][0]["prepare_parallel"] == ["SYS-01", "UI-01"], "M1 wave 0: one Studio writer, preparation in parallel", m["M1"][0])
check(m["M1"][1]["studio_queue"] == ["MAP-02"] and m["M1"][1]["prepare_parallel"] == ["SYS-02", "SYS-03"], "M1 wave 1", m["M1"][1])
check(m["M1"][2]["studio_queue"] == ["UI-02"] and m["M1"][2]["prepare_parallel"] == [], "M1 wave 2", m["M1"][2])
d = waves(FIX / "no-surface.csv", "b")
m = by_milestone(d)
check(m["M1"][0]["studio_queue"] == ["MAP-01", "SYS-01", "UI-01"] and m["M1"][0]["prepare_parallel"] == [], "no surface column: everything goes through Studio", m["M1"][0])

print("workflow C (mixed)")
d = waves(FIX / "good.csv", "c")
m = by_milestone(d)
check(m["M1"][0]["file_lane"] == ["SYS-01", "UI-01"] and m["M1"][0]["studio_lane"] == ["MAP-01"] and m["M1"][0]["sync_points"] == [], "M1 wave 0: two lanes, no sync yet", m["M1"][0])
check(m["M1"][1]["sync_points"] == [{"task": "MAP-02", "after": ["SYS-01"]}], "M1 wave 1: MAP-02 waits for SYS-01 to be synced", m["M1"][1])
check(m["M1"][2]["sync_points"] == [{"task": "UI-02", "after": ["SYS-02", "UI-01"]}], "M1 wave 2: UI-02 waits for both file tasks", m["M1"][2])

print("resume (done tasks)")
for wf, key in (("a", "sub_waves"), ("b", "studio_queue"), ("c", "studio_lane")):
    d = waves(FIX / "resume.csv", wf)
    text = json.dumps(d["milestones"])
    check(all(t not in text for t in ("SYS-01", "MAP-01", "UI-01")), f"workflow {wf}: done tasks are gone from the waves", text)
d = waves(FIX / "resume.csv", "c")
check(by_milestone(d)["M1"][0]["sync_points"] == [], "workflow c: no sync point for a file task that is already done")

print("--next")
d = waves(FIX / "good.csv", "c", "--next")
check(len(d["milestones"]) == 1 and len(d["milestones"][0]["waves"]) == 1 and d["milestones"][0]["milestone"] == "M1", "only the first wave of the first unfinished milestone", d)
rows = (FIX / "good.csv").read_text().splitlines()
tmp = [rows[0]] + [r.rsplit(",", 1)[0] + ",done" for r in rows[1:]]
import tempfile
with tempfile.TemporaryDirectory() as td:
    p = Path(td) / "all-done.csv"
    p.write_text("\n".join(tmp) + "\n")
    d = waves(p, "a", "--next")
    check(d is not None and d["milestones"] == [], "everything done: nothing left", d)

print("broken input")
for name, wf, needle in (
    ("cycle.csv", "a", "dependency cycle"),
    ("unknown-dep.csv", "a", "unknown dependency"),
    ("backward.csv", "a", "milestone"),
    ("no-surface.csv", "c", "surface"),
):
    code, out, err = run(FIX / name, "--workflow", wf)
    check(code == 1 and "ERROR" in err and needle in err, f"{name} (workflow {wf}) fails with '{needle}'", err)
code, out, err = run(FIX / "cycle.csv", "--workflow", "a")
check("A-1" in err and "A-2" in err and "A-3" in err, "cycle message names the tasks in the cycle", err)

print("plain-text output")
code, out, err = run(FIX / "good.csv", "--workflow", "c")
check(code == 0 and "M1" in out and "MAP-02" in out and "sync" in out.lower(), "readable table is printed without --json", out)

# Real plan: Undead Eats converted to tasks.csv
print("Undead Eats production plan")
conv = Path(__file__).resolve().parent / "plan_to_csv.py"
if conv.exists():
    with tempfile.TemporaryDirectory() as td:
        csv_path = Path(td) / "tasks.csv"
        p = subprocess.run([sys.executable, "-I", str(conv), str(ROOT / "examples/undead-eats/PRODUCTION_PLAN.md"), str(csv_path)], capture_output=True, text=True)
        check(p.returncode == 0, "plan converts to tasks.csv", p.stderr)
        ids = [l.split(",")[0] for l in csv_path.read_text().splitlines()[1:]] if p.returncode == 0 else []
        check(len(ids) >= 40, f"{len(ids)} tasks found in the plan")
        for wf in ("a", "b", "c"):
            d = waves(csv_path, wf)
            if d is None:
                continue
            seen = []

            def collect(x):
                if isinstance(x, dict):
                    for k, v in x.items():
                        if k in ("sub_waves", "prepare_parallel", "studio_queue", "file_lane", "studio_lane"):
                            flat = [t for item in v for t in (item if isinstance(item, list) else [item])]
                            seen.extend(flat)
                        else:
                            collect(v)
                elif isinstance(x, list):
                    for i in x:
                        collect(i)

            collect(d["milestones"])
            check(sorted(seen) == sorted(ids), f"workflow {wf}: every task appears exactly once", f"missing {set(ids) - set(seen)}, extra {len(seen) - len(set(seen))}")
else:
    print("  (plan_to_csv.py not written yet)")

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
