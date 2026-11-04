#!/usr/bin/env bash
# SessionStart hook: valid JSON, mentions roblox-start, hooks.json points at an executable script.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS="$ROOT/plugins/roblox-studio/hooks"
fail() { echo "FAIL: $*" >&2; exit 1; }

[ -x "$HOOKS/session-start" ] || fail "session-start is not executable"
out="$("$HOOKS/session-start")"
python3 - "$out" <<'PY' || fail "hook output is not the expected JSON"
import json, sys
d = json.loads(sys.argv[1])["hookSpecificOutput"]
assert d["hookEventName"] == "SessionStart"
c = d["additionalContext"]
assert "roblox-start" in c and "AskUserQuestion" in c and "\n" in c
PY

python3 - "$HOOKS/hooks.json" <<'PY' || fail "hooks.json is wrong"
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]["SessionStart"][0]
assert h["matcher"] == "startup|clear"
assert h["hooks"][0]["command"].endswith('/hooks/session-start"')
PY
[ -d "$ROOT/plugins/roblox-studio/skills/roblox-start" ] || fail "roblox-start skill missing"
echo "hooks ok"
