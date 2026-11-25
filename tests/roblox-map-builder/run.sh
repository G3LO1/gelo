#!/usr/bin/env bash
# Tests for the roblox-map-builder skill: slice acceptance (slice_check.luau on built test slices,
# the command line on .rbxl/.rbxm files, the walkthrough scene it writes, checked with the launch
# kit's scene_spec.py) and fair variant comparisons (compare_variants.py on generated shots).
# Needs: python3 + pillow, lune. Run from the repo root: bash tests/roblox-map-builder/run.sh
set -u
SKILL=plugins/roblox-studio/skills/roblox-map-builder
HERE=tests/roblox-map-builder
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; }

echo "slice acceptance (slice_check.luau)"
lune run $HERE/slice_test "$TMP" > "$TMP/slice.txt"; code=$?
sed 's/^/  /' "$TMP/slice.txt" | grep -E "FAIL|passed"
[ $code -eq 0 ] && ok "good slice passes, 12 broken slices each reported for their own reason" || { bad "slice_test.luau"; cat "$TMP/slice.txt"; }
lune run $SKILL/scripts/slice_check.luau "$TMP/good.rbxl" --scene "$TMP/SliceWalk.json" > "$TMP/cli.txt"; code=$?
[ $code -eq 0 ] && grep -q "^0 failed" "$TMP/cli.txt" && [ -s "$TMP/SliceWalk.json" ] && ok "command line on a place file: exit 0, walkthrough scene written" || { bad "slice CLI on good.rbxl"; cat "$TMP/cli.txt"; }
lune run $SKILL/scripts/slice_check.luau "$TMP/lowdoor.rbxm" > "$TMP/cli.txt"; code=$?
[ $code -eq 1 ] && grep -q "FAIL  door FrontDoor: 6 studs high" "$TMP/cli.txt" && ok "command line on a model file with a low door: exit 1" || { bad "slice CLI on lowdoor.rbxm"; cat "$TMP/cli.txt"; }
python3 plugins/roblox-studio/skills/roblox-launch-kit/scripts/scene_spec.py check "$TMP/SliceWalk.json" > "$TMP/scene.txt"; code=$?
[ $code -eq 0 ] && grep -q "scene SliceWalk: 7.50 s, 4 camera key(s), 0 actor(s), 0 event(s), 4 shot(s)" "$TMP/scene.txt" \
	&& ok "the walkthrough is a valid ShotDirector scene (4 eye-height keys and shots)" || { bad "walkthrough scene"; cat "$TMP/scene.txt"; }

echo "fair comparisons (compare_variants.py)"
cp $SKILL/assets/examples/compare.json "$TMP/compare.json"
python3 - "$TMP" <<'PY'
import json, os, sys
from PIL import Image, ImageDraw
tmp = sys.argv[1]
scene = json.load(open(f"{tmp}/SliceWalk.json"))
os.makedirs(f"{tmp}/ref", exist_ok=True)
def picture(path, color, size=(1280, 720), mark=0):
    img = Image.new("RGB", size, color)
    d = ImageDraw.Draw(img)
    d.rectangle([size[0] // 4 + mark, size[1] // 4, size[0] // 2 + mark, size[1] - 40], fill=(240, 220, 180))
    img.save(path)
picture(f"{tmp}/ref/spice-hall.png", (120, 80, 50))
picture(f"{tmp}/ref/desert-town.png", (200, 170, 110))
for variant, color in (("pass1", (90, 90, 90)), ("pass2", (110, 70, 40)), ("other", (60, 60, 120))):
    os.makedirs(f"{tmp}/shots/{variant}", exist_ok=True)
    for i, shot in enumerate(s["name"] for s in scene["shots"]):
        picture(f"{tmp}/shots/{variant}/{shot}.png", color, mark=i * 40)
base = json.load(open(f"{tmp}/compare.json"))
def case(name, mutate):
    data = json.loads(json.dumps(base)); mutate(data); json.dump(data, open(f"{tmp}/{name}.json", "w"))
other = lambda d: d["variants"].append({**d["variants"][1], "name": "OtherModel", "reference": "ref/desert-town.png", "shots": "shots/other"})
case("otherref", other)
open(f"{tmp}/OtherWalk.json", "w").write(open(f"{tmp}/SliceWalk.json").read().replace('"fov": 70', '"fov": 60'))
case("othercam", lambda d: d["variants"][1].__setitem__("scene", "OtherWalk.json"))
os.remove(f"{tmp}/shots/other/Interior.png")
case("missingshot", lambda d: d["variants"][1].__setitem__("shots", "shots/other"))
case("unscored", lambda d: (d["variants"][0]["scores"].pop("Interior"), d["variants"][1]["scores"].__setitem__("Vibes", 5), d["variants"][1]["scores"].__setitem__("Performance", 9)))
Image.new("RGB", (640, 360), (0, 0, 0)).save(f"{tmp}/shots/pass2/Route.png")  # one view captured smaller
case("sizes", lambda d: d["variants"][0].__setitem__("slice", "fail: door 6 studs"))
PY
CV="python3 $SKILL/scripts/compare_variants.py"
expect() { grep -qE "$2" "$TMP/$1.txt" && ok "$3" || { bad "$3"; cat "$TMP/$1.txt"; }; }
# the example manifest on the generated shots (pass2's Route shot is deliberately captured smaller)
$CV "$TMP/compare.json" --html "$TMP/compare.html" > "$TMP/good.txt"; code=$?
[ $code -eq 0 ] && grep -q "^0 error(s), 1 warning(s)" "$TMP/good.txt" && ok "example comparison: same reference, same camera, every criterion scored: no errors" || { bad "example comparison"; cat "$TMP/good.txt"; }
expect good "WARN  Route: shots at different sizes \(Pass1Draft 1280x720, Pass2Final 640x360\)" "shots of one view at different sizes warn"
expect good "Pass2Final: total 20 over 5 criteria, 4/4 shots" "scores totalled per variant, all 4 shots found"
grep -q "Same views, side by side" "$TMP/compare.html" && grep -q "<th>Pass1Draft</th><th>Pass2Final</th>" "$TMP/compare.html" && grep -q "data:image/jpeg;base64" "$TMP/compare.html" \
	&& ok "HTML: reference + variants per view, score table" || bad "compare HTML"
for c in otherref othercam missingshot unscored sizes; do $CV "$TMP/$c.json" > "$TMP/$c.txt"; echo "exit $?" >> "$TMP/$c.txt"; done
expect otherref "ERROR OtherModel: built from another reference \(desert-town.png\): not comparable" "a variant built from another concept is not comparable"
expect othercam "ERROR Pass2Final: shots taken with another scene \(OtherWalk.json\): different camera" "a variant shot with another camera is not comparable"
expect missingshot "ERROR Pass2Final: missing shot Interior" "missing shot"
expect unscored "ERROR Pass1Draft: 'Interior' needs a score from 1 to 5" "missing score"
expect unscored "ERROR Pass2Final: score for unknown criterion 'Vibes'" "unknown criterion"
expect unscored "ERROR Pass2Final: 'Performance' needs a score from 1 to 5" "score out of range"
expect sizes "WARN  Pass1Draft: slice check: fail: door 6 studs" "a variant whose slice didn't pass is flagged"
grep -q "exit 1" "$TMP/otherref.txt" && grep -q "exit 0" "$TMP/sizes.txt" && ok "errors exit 1, warnings alone exit 0" || bad "exit codes"

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
