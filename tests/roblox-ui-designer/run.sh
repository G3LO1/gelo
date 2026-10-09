#!/usr/bin/env bash
# Pipeline tests for the roblox-ui-designer skill: spec -> Luau -> Lune validation (real Roblox
# API database), negative cases, and a generated PSD through psd_to_spec.py.
# Needs: python3, lune, pip install psd-tools pillow. Run from the repo root:
#   bash tests/roblox-ui-designer/run.sh
set -u
SKILL=plugins/roblox-studio/skills/roblox-ui-designer
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; }

echo "example spec builds and validates"
if python3 $SKILL/scripts/spec_to_luau.py $SKILL/assets/examples/style-tile-bubbly.json -o $TMP/tile.luau 2>$TMP/warn.txt \
	&& lune run $SKILL/scripts/validate_ui.luau $TMP/tile.luau $TMP/tile.rbxmx | grep -q "^OK"; then ok "style tile"; else bad "style tile"; fi
[ ! -s $TMP/warn.txt ] && ok "example has no layout warnings" || bad "example has layout warnings: $(cat $TMP/warn.txt)"
[ -s $TMP/tile.rbxmx ] && ok ".rbxmx written" || bad ".rbxmx missing"

echo "broken specs are rejected"
python3 - "$SKILL" "$TMP" <<'PY'
import copy, json, sys
skill, tmp = sys.argv[1], sys.argv[2]
base = json.load(open(f"{skill}/assets/examples/style-tile-bubbly.json"))
panel = lambda s: s["screens"][0]["children"][1]
cases = {
    "badprop": lambda s: panel(s)["props"].__setitem__("BackgroundColour3", {"color": "#FFFFFF"}),
    "badenum": lambda s: panel(s)["props"].__setitem__("AutomaticSize", {"enum": "AutomaticSize.Sideways"}),
    "badtype": lambda s: panel(s)["props"].__setitem__("Size", {"udim": [1, 0]}),
    "badclass": lambda s: panel(s)["children"].append({"class": "UIRoundCorner"}),
    "badstyle": lambda s: s["styles"].append({"selector": "TextLabel", "props": {"TextSize": {"token": "Primary"}}}),
    "badtoken": lambda s: panel(s)["props"].__setitem__("BackgroundColor3", {"token": "Nope"}),
    "badcolor": lambda s: panel(s)["props"].__setitem__("BackgroundColor3", {"color": "red"}),
}
for name, mutate in cases.items():
    spec = copy.deepcopy(base); mutate(spec)
    json.dump(spec, open(f"{tmp}/{name}.json", "w"))
zero = copy.deepcopy(base)
panel(zero)["props"]["Size"] = {"udim2": [1, 0, 0, 0]}
json.dump(zero, open(f"{tmp}/zero.json", "w"))
PY
for name in badprop badenum badtype badclass badstyle badtoken badcolor; do
	if python3 $SKILL/scripts/spec_to_luau.py $TMP/$name.json -o $TMP/$name.luau 2>/dev/null; then
		lune run $SKILL/scripts/validate_ui.luau $TMP/$name.luau >/dev/null 2>&1 && bad "$name accepted" || ok "$name rejected by validator"
	else
		ok "$name rejected by spec check"
	fi
done
python3 $SKILL/scripts/spec_to_luau.py $TMP/zero.json -o $TMP/zero.luau 2>&1 | grep -q "zero on one axis" && ok "zero-size layout warned" || bad "zero-size layout not warned"

echo "PSD export"
python3 - "$TMP" <<'PY'
import sys
from psd_tools import PSDImage
from PIL import Image, ImageDraw
tmp = sys.argv[1]
def box(w, h, c):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0)); ImageDraw.Draw(im).rounded_rectangle([0, 0, w - 1, h - 1], 16, fill=c); return im
psd = PSDImage.new("RGBA", (1920, 1080))
bar = psd.create_pixel_layer(box(360, 90, (43, 47, 119, 255)), name="Coin Bar #slice=40", top=20, left=20)
hp = psd.create_pixel_layer(box(300, 60, (255, 77, 94, 255)), name="Health", top=1000, left=1600)
hidden = psd.create_pixel_layer(box(100, 100, (0, 255, 0, 255)), name="Hidden", top=500, left=500); hidden.visible = False
note = psd.create_pixel_layer(box(200, 50, (255, 255, 0, 255)), name="Notes #skip", top=900, left=100)
psd.create_group([bar, hp, hidden, note], name="HUD")
items = [psd.create_pixel_layer(box(150, 150, (63, 169, 245, 255)), name=f"Item {i}", top=400, left=980 - i * 170) for i in range(3)]
row = psd.create_group(items, name="Items #list-h=12")
psd.create_group([row], name="Shop")
psd.save(f"{tmp}/test.psd")
PY
if python3 $SKILL/scripts/psd_to_spec.py $TMP/test.psd -o $TMP/psd --name PsdTest >/dev/null; then ok "psd_to_spec ran"; else bad "psd_to_spec failed"; fi
python3 - "$TMP" <<'PY' && ok "PSD conventions (hidden/#skip dropped, 9-slice, anchors, list order by position)" || bad "PSD conventions"
import json, sys
spec = json.load(open(f"{sys.argv[1]}/psd/ui-spec.json"))
hud = next(s for s in spec["screens"] if s["name"] == "HUD")
names = [c["name"] for c in hud["children"]]
assert names == ["Coin_Bar", "Health"], names
bar, hp = hud["children"]
assert bar["props"]["SliceCenter"] == {"rect": [40, 40, 320, 50]}, bar["props"]
assert hp["props"]["AnchorPoint"] == {"vector2": [1, 1]}, hp["props"]["AnchorPoint"]
shop = next(s for s in spec["screens"] if s["name"] == "Shop")
row = shop["children"][0]
order = {c["name"]: c["props"]["LayoutOrder"] for c in row["children"] if c["class"] == "ImageLabel"}
assert order == {"Item_2": 1, "Item_1": 2, "Item_0": 3}, order  # Item 2 is leftmost
PY
python3 $SKILL/scripts/spec_to_luau.py $TMP/psd/ui-spec.json -o $TMP/psd.luau 2>/dev/null && lune run $SKILL/scripts/validate_ui.luau $TMP/psd.luau | grep -q "^OK" && ok "PSD spec validates" || bad "PSD spec does not validate"
python3 $SKILL/scripts/preview_ui.py $SKILL/assets/examples/style-tile-bubbly.json -o $TMP/preview.html >/dev/null && grep -q "BubblyStyleTile" $TMP/preview.html && ok "preview HTML written" || bad "preview failed"

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
