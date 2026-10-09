"""Compares scan_luau.py findings with the `-- expect: RULE, RULE` header of every fixture file
(exact multiset per file, so both misses and false positives fail).
Usage: python3 check_fixtures.py <findings.json> <fixtures-dir>"""

import collections
import json
import os
import re
import sys

findings = json.load(open(sys.argv[1]))["findings"]
root = sys.argv[2]
got = collections.defaultdict(list)
for f in findings:
    got[os.path.normpath(f["file"])].append(f["rule"])

failed = 0
for dirpath, _, files in os.walk(root):
    for name in sorted(files):
        if not name.endswith(".luau"):
            continue
        path = os.path.normpath(os.path.join(dirpath, name))
        header = open(path).readline()
        m = re.match(r"--\s*expect:(.*)", header)
        if not m:
            print(f"  FAIL {path}: missing '-- expect:' header")
            failed += 1
            continue
        expected = sorted(r.strip() for r in m.group(1).split(",") if r.strip())
        actual = sorted(got.get(path, []))
        if expected == actual:
            print(f"  ok   {os.path.relpath(path, root)} ({len(actual)} findings)")
        else:
            failed += 1
            missing = list((collections.Counter(expected) - collections.Counter(actual)).elements())
            extra = list((collections.Counter(actual) - collections.Counter(expected)).elements())
            print(f"  FAIL {os.path.relpath(path, root)}: missing {missing}, unexpected {extra}")
sys.exit(1 if failed else 0)
