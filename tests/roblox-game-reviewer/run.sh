#!/usr/bin/env bash
# Tests for roblox-game-reviewer: scoring script (math, verdicts, blockers, validation, progress) and the
# project state collector. Needs python3. Run from the repo root: bash tests/roblox-game-reviewer/run.sh
set -u
S=plugins/roblox-studio/skills/roblox-game-reviewer
SCORE=$S/scripts/review_score.py
COLLECT=$S/scripts/collect_state.py
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; }
has() { grep -qE -- "$2" "$1" && ok "$3" || { bad "$3"; sed 's/^/       /' "$1" | head -20; }; }

# mk <file> <score for all> [extra python to mutate d]
mk() {
python3 - "$@" <<'PY'
import json, sys
path, score = sys.argv[1], int(sys.argv[2])
extra = sys.argv[3] if len(sys.argv) > 3 else ""
keys = ["core_loop","onboarding","progression","ux_mobile","polish","content","monetization","stability"]
d = {"game": "T", "scores": {k: {"score": score, "evidence": "checked in a playtest with three full runs"} for k in keys},
     "improvements": [{"title": "fix onboarding", "criterion": "onboarding", "impact": 4, "effort": 2, "why": "w"}]}
exec(extra)
json.dump(d, open(path, "w"))
PY
}

echo "example review"
python3 $SCORE $S/assets/example-review.json > $TMP/ex.txt 2>$TMP/ex.err
[ $? -eq 0 ] && ok "example passes with exit 0" || bad "example failed"
has $TMP/ex.txt "NEEDS WORK \(59\.6/100\)" "total 59.6 by weighted points"
has $TMP/ex.txt "\| 1 \| Do now \| Rate-limit" "highest impact/effort first"
has $TMP/ex.txt "Later \| Localize" "low ratio is Later"

echo "verdict thresholds"
for pair in "5 80 SHIP-READY 100" "4 80 SHIP-READY 80" "3 60 NEEDS WORK 60" "2 40 BROKEN 40"; do
  set -- $pair
  mk $TMP/v.json $1 'd["improvements"]+= [{"title":"x","criterion":k,"impact":1,"effort":1,"why":"w"} for k in keys]'
  python3 $SCORE $TMP/v.json > $TMP/v.txt 2>/dev/null
  case "$1" in
    5|4) has $TMP/v.txt "SHIP-READY \($4/100\)" "all $1s -> $4 -> SHIP-READY";;
    3) has $TMP/v.txt "NEEDS WORK \(60/100\)" "all 3s -> 60 -> NEEDS WORK";;
    2) has $TMP/v.txt "BROKEN \(40/100\)" "all 2s -> 40 -> BROKEN";;
  esac
done
mk $TMP/solid.json 4 'd["scores"]["core_loop"]["score"]=3; d["scores"]["polish"]["score"]=3'
python3 $SCORE $TMP/solid.json > $TMP/solid.txt 2>/dev/null
has $TMP/solid.txt "SOLID \(74/100\)" "mixed 4/3 -> 74 -> SOLID"

echo "blockers cap the verdict"
mk $TMP/cap.json 5 'd["blockers"]=[{"title":"client grants currency","criterion":"stability","evidence":"SEC-001 Shop.server.luau:42"}]'
python3 $SCORE $TMP/cap.json > $TMP/cap.txt 2>/dev/null
has $TMP/cap.txt "NEEDS WORK \(100/100\)" "100 points but blocker -> NEEDS WORK"
has $TMP/cap.txt "capped to NEEDS WORK by 1 blocker" "says why it was capped"
has $TMP/cap.txt "Blockers \(fix before shipping\)" "blocker section"

echo "validation"
mk $TMP/e1.json 3 'del d["scores"]["polish"]'
python3 $SCORE $TMP/e1.json >/dev/null 2>$TMP/e1.txt; [ $? -eq 1 ] && ok "missing criterion -> exit 1" || bad "missing criterion exit"
has $TMP/e1.txt "scores.polish: missing" "names the missing criterion"
mk $TMP/e2.json 3 'd["scores"]["core_loop"]["score"]=6'
python3 $SCORE $TMP/e2.json >/dev/null 2>$TMP/e2.txt
has $TMP/e2.txt "scores.core_loop: 'score' must be an integer 1-5" "score 6 rejected"
mk $TMP/e3.json 3 'd["scores"]["content"]["evidence"]="  "'
python3 $SCORE $TMP/e3.json >/dev/null 2>$TMP/e3.txt
has $TMP/e3.txt "scores.content: 'evidence' is required" "empty evidence rejected"
mk $TMP/e4.json 3 'd["scores"]["fun"]={"score":3,"evidence":"x"}'
python3 $SCORE $TMP/e4.json >/dev/null 2>$TMP/e4.txt
has $TMP/e4.txt "scores.fun: unknown criterion" "unknown criterion rejected"
mk $TMP/e5.json 3 'd["scores"]["monetization"]["score"]=1'
python3 $SCORE $TMP/e5.json >/dev/null 2>$TMP/e5.txt
has $TMP/e5.txt "scores.monetization: scored 1 .* no improvement or blocker targets it" "weak area needs an improvement"
mk $TMP/e6.json 3 'd["improvements"][0]["effort"]=0'
python3 $SCORE $TMP/e6.json >/dev/null 2>$TMP/e6.txt
has $TMP/e6.txt "improvements\[0\]: 'effort' must be an integer 1-5" "effort 0 rejected"
mk $TMP/w1.json 3 'pass'
python3 $SCORE $TMP/w1.json --strict >/dev/null 2>$TMP/w1.txt; [ $? -eq 1 ] && ok "identical scores warn; --strict exits 1" || bad "--strict"
has $TMP/w1.txt "same score" "warning text"
python3 $SCORE $TMP/w1.json >/dev/null 2>&1; [ $? -eq 0 ] && ok "warning alone exits 0 without --strict" || bad "warning exit"
python3 $SCORE $TMP/nonexistent.json >/dev/null 2>$TMP/ne.txt; [ $? -ne 0 ] && ok "missing file fails" || bad "missing file"

echo "progress against a previous review"
python3 $SCORE $S/assets/example-review.json --json $TMP/prev.json > /dev/null 2>&1
python3 - "$S/assets/example-review.json" "$TMP/next.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["scores"]["onboarding"]["score"] = 4
d["scores"]["ux_mobile"]["score"] = 4
json.dump(d, open(sys.argv[2], "w"))
PY
python3 $SCORE $TMP/next.json --previous $TMP/prev.json > $TMP/next.txt 2>/dev/null
has $TMP/next.txt "59\.6 -> 69\.2" "previous total -> new total"
has $TMP/next.txt "NEEDS WORK -> SOLID" "verdict change"
has $TMP/next.txt "\| \+4\.8 \|" "per-criterion change column"
python3 $SCORE $TMP/next.json --previous $S/assets/example-review.json > $TMP/next2.txt 2>/dev/null
has $TMP/next2.txt "59\.6 -> 69\.2" "--previous also takes a raw review.json"

echo "state collector"
G=$TMP/game
mkdir -p $G/src/server/Services $G/src/client $G/src/shared $G/tests
cat > $G/default.project.json <<'J'
{"name":"TestGame","tree":{"$className":"DataModel","Workspace":{"$properties":{"StreamingEnabled":true}}}}
J
cat > $G/src/server/Services/Data.luau <<'L'
local DataStoreService = game:GetService("DataStoreService")
game:BindToClose(function() end)
-- local LocalizationTable = nothing: this comment must not count
L
cat > $G/src/server/Services/Shop.server.luau <<'L'
MarketplaceService.ProcessReceipt = function() end
local Config = { Pass = 0, -- TODO: paste ID from Creator Hub
}
Config.Greybox = true
local price = "Buy for 499 Robux"
L
cat > $G/src/client/Hud.client.luau <<'L'
local gui = Instance.new("ScreenGui")
L
echo "return {}" > $G/src/shared/Config.luau
echo "test" > $G/tests/a.luau
python3 $COLLECT $G --json $TMP/state.json > $TMP/state.txt
[ $? -eq 0 ] && ok "collector exits 0" || bad "collector failed"
has $TMP/state.txt "State of TestGame" "uses Rojo project name"
has $TMP/state.txt "server 2, client 1, shared 1" "scripts by side (incl .server/.client suffix)"
has $TMP/state.txt "StreamingEnabled: True" "StreamingEnabled read from project.json"
has $TMP/state.txt "player data saving: 1 file" "finds DataStore use"
has $TMP/state.txt "BindToClose: 1 file" "finds BindToClose"
has $TMP/state.txt "purchases: 1 file" "finds ProcessReceipt"
has $TMP/state.txt "localization: 0 file" "ignores words inside comments"
has $TMP/state.txt "audio: 0 file" "reports absent audio"
has $TMP/state.txt "Config.Greybox = true" "greybox flag listed"
has $TMP/state.txt "Pass = 0, -- TODO" "placeholder ID listed"
has $TMP/state.txt "Buy for 499 Robux" "hard-coded Robux price listed"
has $TMP/state.txt "tests/a.luau" "tests detected"
python3 -c "import json;d=json.load(open('$TMP/state.json'));assert d['project']['scripts']==5 and d['todos']['count']==1" && ok "--json has the same facts" || bad "--json"
mkdir -p $TMP/empty
python3 $COLLECT $TMP/empty > $TMP/empty.txt
has $TMP/empty.txt "No Luau scripts or place files" "empty folder explained"
python3 $COLLECT $TMP/nope >/dev/null 2>&1; [ $? -ne 0 ] && ok "missing folder fails" || bad "missing folder"

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
