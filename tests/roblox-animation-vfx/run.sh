#!/usr/bin/env bash
# Tests for the roblox-animation-vfx skill: Vfx presets against Roblox's API database, the
# showcase model, AnimationSet behaviour, the manifest validator/generator and the textures.
# Needs: python3 + pillow, lune. Run from the repo root: bash tests/roblox-animation-vfx/run.sh
set -u
SKILL=plugins/roblox-studio/skills/roblox-animation-vfx
HERE=tests/roblox-animation-vfx
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; }
expect() { grep -qE "$1" "$TMP/bad.txt" && ok "bad manifest: $2" || bad "bad manifest: $2"; }

echo "animation manifest"
python3 $SKILL/scripts/anim_manifest.py $HERE/good.json -o $TMP/Animations.luau > $TMP/strict.txt
[ $? -eq 1 ] && grep -q "error: animations\[3\] Victory: no asset id yet" $TMP/strict.txt && ok "missing id is an error by default" || bad "missing id without --allow-todo"
python3 $SKILL/scripts/anim_manifest.py $HERE/good.json -o $TMP/Animations.luau --allow-todo > $TMP/good.txt
[ $? -eq 0 ] && grep -q "0 error(s), 0 warning(s), 1 todo(s)" $TMP/good.txt && ok "good manifest: no errors or warnings, 1 todo" || { bad "good manifest:"; cat $TMP/good.txt; }
grep -q 'Chop = { Id = "rbxassetid://12", Priority = Enum.AnimationPriority.Action, Looped = false, Markers = { "Hit" } },' $TMP/Animations.luau \
	&& grep -q 'Victory = { Id = "rbxassetid://0".* -- TODO' $TMP/Animations.luau && ok "generated module" || { bad "generated module:"; cat $TMP/Animations.luau; }
python3 $SKILL/scripts/anim_manifest.py $HERE/bad.json > $TMP/bad.txt; [ $? -eq 1 ] && ok "bad manifest exits 1" || bad "bad manifest exit code"
expect "warning: no 'owner'" "missing owner"
expect "Run: locomotion at Action" "locomotion priority too high"
expect "Run: 'Run' usually loops" "locomotion not looped"
expect "Slash: one-off action at Movement" "action priority too low"
expect "Slash: one-off action marked looped" "action looped"
expect "Slash: add a marker" "timed action without marker"
expect "error: animations\[2\] Slash: duplicate name" "duplicate name"
expect "warning: animations\[2\] Slash: same id as Slash" "duplicate id"
expect "Wave Hello: name must be a Luau identifier" "invalid name"
expect "Wave Hello: no asset id yet" "invalid id"
expect "Wave Hello: priority 'Emote'" "invalid priority"
expect "OldPunch: made for R6" "rig mismatch"
expect "Throw: set 'looped' explicitly" "looped missing"
expect "Blend: animation graph without 'parameters'" "graph without parameters"

echo "Vfx and AnimationSet (Lune, real API database)"
lune run $HERE/vfx_test $TMP/Animations.luau > $TMP/vfx.txt; code=$?
sed 's/^/  /' $TMP/vfx.txt | grep -E "ok|FAIL|passed|    "
[ $code -eq 0 ] && ok "vfx_test.luau (with the generated Animations module)" || bad "vfx_test.luau"
lune run $SKILL/scripts/vfx_showcase.luau $SKILL/assets/Vfx.luau $TMP/VfxShowcase.rbxmx | grep -q "^OK" && [ -s $TMP/VfxShowcase.rbxmx ] \
	&& ok "showcase model builds" || bad "showcase model"
lune run $SKILL/scripts/vfx_showcase.luau $SKILL/assets/Vfx.luau --quality 0.3 --reduced-flashing | grep -q "^OK" && ok "showcase at low quality + reduced flashing" || bad "showcase low quality"
sed 's/emitter.LightEmission = spec.lightEmission or 0/emitter.LightEmmission = spec.lightEmission or 0/' $SKILL/assets/Vfx.luau > $TMP/BrokenVfx.luau
lune run $SKILL/scripts/vfx_showcase.luau $TMP/BrokenVfx.luau | grep -q "LightEmmission is not a valid member" && ok "a property typo is caught" || bad "property typo not caught"

echo "textures"
python3 $SKILL/scripts/make_textures.py $TMP/textures > /dev/null
python3 - "$TMP/textures" "$SKILL/assets/textures" <<'PY' && ok "generator output matches the committed textures, 128x128 RGBA" || bad "textures"
import sys
from PIL import Image, ImageChops
new, committed = sys.argv[1], sys.argv[2]
for name in ["glow", "star", "spark", "smoke", "ring"]:
    a, b = Image.open(f"{new}/{name}.png"), Image.open(f"{committed}/{name}.png")
    assert a.size == (128, 128) and a.mode == "RGBA", name
    # small tolerance: blur/resampling differ slightly between Pillow versions
    worst = max(hi for _, hi in ImageChops.difference(a, b).getextrema())
    assert worst <= 16, f"{name} differs from the committed file (max channel diff {worst})"
    assert a.getchannel("A").getextrema()[1] > 200, f"{name} is empty"
PY

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
