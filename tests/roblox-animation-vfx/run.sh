#!/usr/bin/env bash
# Tests for the roblox-animation-vfx skill: Vfx presets against Roblox's API database, the
# showcase model, AnimationSet behaviour, the manifest validator/generator, flipbook sheets
# (flipbook.py pack/check/preview), the textures, and with bpy blender_check.py and the
# model_batch.py pipeline (+ its ModelSpecs.luau under Lune) and anim_accept.py; sound effects
# (sfx_manifest.py on generated takes, Sfx.luau).
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

echo "acceptance fields (rigs, idR6, accept) and the R15 + R6 example"
EX=$SKILL/assets/examples/animations.json
python3 $SKILL/scripts/anim_manifest.py $EX --allow-todo -o $TMP/ExampleAnimations.luau > $TMP/ex.txt
[ $? -eq 0 ] && grep -q "0 error(s), 0 warning(s), 4 todo(s)" $TMP/ex.txt && grep -q "Animations.SpecsR6 = {" $TMP/ExampleAnimations.luau && grep -q "function Animations.specsFor" $TMP/ExampleAnimations.luau \
	&& ok "example manifest: R15 + R6 specs, 4 todo ids (R15 and R6), specsFor()" || { bad "example manifest:"; cat $TMP/ex.txt; }
python3 $SKILL/scripts/anim_manifest.py $HERE/bad_accept.json > $TMP/bad.txt; [ $? -eq 1 ] && ok "bad accept manifest exits 1" || bad "bad accept exit code"
expect "manifest: accept.slideTolerance must be a number >= 0" "negative tolerance"
expect "manifest: accept.grounded is not a known setting" "per-animation key at manifest level"
expect "Walk: no R6 asset id yet \(idR6" "missing idR6 when the game ships R6"
expect "Walk: locomotion without 'accept'" "locomotion not covered by acceptance"
expect "Chop: idR6 is the R15 id" "R6 reuses the R15 upload"
expect "Chop: accept.wobble is not a known setting" "unknown accept key"
expect "Chop: accept.grounded must be true or false" "accept type"
expect "Chop: accept.grips needs accept.prop" "grips without a prop"
echo '{"rig": "R6", "rigs": ["R15", "R6"], "owner": "x", "animations": []}' > $TMP/rigs.json
python3 $SKILL/scripts/anim_manifest.py $TMP/rigs.json > $TMP/bad.txt
expect "rigs starts with R15 but rig is R6" "rig and rigs disagree"

echo "Vfx and AnimationSet (Lune, real API database)"
lune run $HERE/animcheck_test $TMP/ExampleAnimations.luau > $TMP/animcheck.txt; code=$?
sed 's/^/  /' $TMP/animcheck.txt | grep -E "FAIL|passed"
[ $code -eq 0 ] && ok "AnimCheck.luau: published clips vs the manifest (markers, loop, priority, R6)" || { bad "AnimCheck.luau"; cat $TMP/animcheck.txt; }
lune run $HERE/vfx_test $TMP/Animations.luau > $TMP/vfx.txt; code=$?
sed 's/^/  /' $TMP/vfx.txt | grep -E "ok|FAIL|passed|    "
[ $code -eq 0 ] && ok "vfx_test.luau (with the generated Animations module)" || bad "vfx_test.luau"
lune run $SKILL/scripts/vfx_showcase.luau $SKILL/assets/Vfx.luau $TMP/VfxShowcase.rbxmx | grep -q "^OK" && [ -s $TMP/VfxShowcase.rbxmx ] \
	&& ok "showcase model builds" || bad "showcase model"
lune run $SKILL/scripts/vfx_showcase.luau $SKILL/assets/Vfx.luau --quality 0.3 --reduced-flashing | grep -q "^OK" && ok "showcase at low quality + reduced flashing" || bad "showcase low quality"
sed 's/emitter.LightEmission = spec.lightEmission or 0/emitter.LightEmmission = spec.lightEmission or 0/' $SKILL/assets/Vfx.luau > $TMP/BrokenVfx.luau
lune run $SKILL/scripts/vfx_showcase.luau $TMP/BrokenVfx.luau | grep -q "LightEmmission is not a valid member" && ok "a property typo is caught" || bad "property typo not caught"

lune run $SKILL/scripts/vfx_showcase.luau $SKILL/assets/Vfx.luau $TMP/Variants.rbxmx | grep -q "^OK: .* (.* pads with variants)" \
	&& grep -q '<string name="Name">Slash_Ember</string>' $TMP/Variants.rbxmx && grep -q '<string name="Name">Slash_Frost</string>' $TMP/Variants.rbxmx \
	&& ok "showcase has a pad per color variant" || bad "showcase variant pads"

echo "flipbook sheets (flipbook.py)"
FB="python3 $SKILL/scripts/flipbook.py"
python3 $HERE/make_flipbooks.py $SKILL/assets/textures/slash_4x4.png $TMP/fb > /dev/null || bad "could not generate flipbook fixtures"
fb() { $FB "$@" > $TMP/fb.txt 2>&1; echo $? >> $TMP/fb.txt; }
has() { grep -qE "$1" $TMP/fb.txt; }
code() { [ "$(tail -n1 $TMP/fb.txt)" = "$1" ]; }
fb check $SKILL/assets/textures/slash_4x4.png --strict
code 0 && has "^0 error\(s\), 0 warning\(s\)" && ok "committed slash_4x4.png: clean 4x4 sheet (--strict)" || { bad "committed sheet:"; cat $TMP/fb.txt; }
fb pack $TMP/fb/frames -o $TMP/fb/round.png
python3 -c "import sys; from PIL import Image, ImageChops; a, b = Image.open(sys.argv[1]), Image.open(sys.argv[2]); assert a.size == b.size and ImageChops.difference(a, b).getbbox() is None" $TMP/fb/round.png $SKILL/assets/textures/slash_4x4.png \
	&& code 0 && ok "pack: 16 frames -> the same sheet (reading order)" || { bad "pack round trip"; cat $TMP/fb.txt; }
fb check $TMP/fb/edge.png
code 1 && has "ERROR frame 6 \(row 2, col 2\): paint 0 px from the right edge" && ok "check: paint on the cell edge is an error" || { bad "edge"; cat $TMP/fb.txt; }
fb check $TMP/fb/near.png --strict
code 1 && has "WARN  frame 2 .*: paint 2 px from the top edge \(keep 4 px" && ok "check: paint inside the margin warns (--strict exits 1)" || { bad "near"; cat $TMP/fb.txt; }
fb check $TMP/fb/empty.png
code 1 && has "ERROR frame 16 .*: empty" && ok "check: empty frame" || { bad "empty"; cat $TMP/fb.txt; }
fb check $TMP/fb/haze.png
code 0 && has "WARN  frame 3 .*faint haze" && ! has "frame (1|2|4) .*haze" && ok "check: grey haze around the shape warns, only on that frame" || { bad "haze"; cat $TMP/fb.txt; }
fb check $TMP/fb/tinted.png
has "WARN  tinted.png: colored pixels in frame\(s\) 1, 2, 3, 4, 5, 6 \.\.\." && ok "check: colored sheet warns (draw in white)" || { bad "tinted"; cat $TMP/fb.txt; }
fb check $TMP/fb/oblong.png; code 1 && has "must be square" && ok "check: non-square sheet" || { bad "oblong"; cat $TMP/fb.txt; }
fb check $TMP/fb/npot.png; code 1 && has "power-of-two" && ok "check: non power-of-two sheet" || { bad "npot"; cat $TMP/fb.txt; }
fb check $TMP/fb/huge.png; code 1 && has "over 1024 px" && ok "check: sheet over 1024 px" || { bad "huge"; cat $TMP/fb.txt; }
fb pack $TMP/fb/big -o $TMP/fb/big.png
code 1 && has "ERROR frame .*paint 0 px" && ok "pack without --fit reports frames that touch the edge" || { bad "pack big"; cat $TMP/fb.txt; }
fb pack $TMP/fb/big -o $TMP/fb/fit.png --fit
code 0 && has "fit: content .* scaled" && has "^0 error\(s\), 0 warning\(s\)" && ok "pack --fit scales all frames alike into the margin" || { bad "pack --fit"; cat $TMP/fb.txt; }
fb pack $TMP/fb/colored.gif -o $TMP/fb/white.png --white
code 0 && has "^0 error\(s\), 0 warning\(s\)" && python3 -c "import sys; from PIL import Image; im = Image.open(sys.argv[1]); assert im.size == (512, 512) and im.getpixel((64, 64))[:3] == (255, 255, 255) and im.getpixel((64, 64))[3] > 100" $TMP/fb/white.png \
	&& ok "pack --white: animated GIF -> white mask sheet" || { bad "pack --white"; cat $TMP/fb.txt; }
fb pack $TMP/fb/many -o $TMP/fb/many.png; code 1 && has "20 frames do not fit a 4x4 grid" && ok "pack: too many frames for the grid" || { bad "many"; cat $TMP/fb.txt; }
fb pack $TMP/fb/many -o $TMP/fb/many8.png --grid 8 --cell 64
code 1 && has "20 frames for 64 cells" && has "ERROR frames 21-64: empty" && [ "$(grep -c "^ERROR.*empty" $TMP/fb.txt)" = 1 ] \
	&& ok "pack: fewer frames leave empty cells, reported once as an error" || { bad "many grid 8"; cat $TMP/fb.txt; }
fb preview $SKILL/assets/textures/slash_4x4.png -o $TMP/fb/preview.html --tint "#96d7ff" --tint "#ffb43c"
code 0 && grep -q "FlipbookLayout Grid4x4" $TMP/fb/preview.html && grep -q "data:image/png;base64" $TMP/fb/preview.html && grep -q "#ffb43c on dark" $TMP/fb/preview.html \
	&& ok "preview: HTML with the sheet, frame highlight and one player per tint" || { bad "preview"; cat $TMP/fb.txt; }

echo "sound effects (sfx_manifest.py on generated test takes, Sfx.luau)"
SX="python3 $SKILL/scripts/sfx_manifest.py"
cp $SKILL/assets/examples/sounds.json $TMP/sounds.json
python3 $HERE/make_sounds.py $TMP > /dev/null || bad "could not generate test takes"
sx() { $SX "$@" > $TMP/sx.txt 2>&1; echo $? >> $TMP/sx.txt; }
said() { grep -qE "$1" $TMP/sx.txt; }
sx check $TMP/sounds.json --animations $SKILL/assets/examples/animations.json --vfx $SKILL/assets/Vfx.luau
[ "$(tail -n1 $TMP/sx.txt)" = 1 ] && ok "check exits 1 on bad takes" || bad "check exit code"
said "ERROR SwordHit\[2\] sfx/SwordHit_2.wav: 450 ms of silence before the sound" && ok "silence before the sound (lag)" || { bad "lead silence"; cat $TMP/sx.txt; }
said "ERROR SwordHit\[3\] .*hits 3[0-9]{2} ms after the Chop:Hit marker .*pick a take that hits at once" && ok "late hit on a marker (build-up)" || { bad "late hit"; cat $TMP/sx.txt; }
said "WARN  Pickup\[1\] .*builds up for 4[0-9]{2} ms" && ok "long build-up on an event sound" || bad "build-up"
said "ERROR Pickup\[1\] .*the sound lasts 1\.[0-9]+ s, max 1 s" && ok "longer than maxLength" || bad "too long"
said "ERROR UiHover\[1\] .*empty: silent all through" && ok "empty take" || bad "empty"
said "WARN  Footstep\[3\] .*clipped samples" && said "WARN  Footstep\[3\] .*loudness -8\.[0-9] dBFS, target -18" && ok "clipping and loudness off target" || bad "clipping/loudness"
said "INFO  Footstep: 1 take\(s\) waiting for moderation" && said "WARN  UiHover: no approved take: plays nothing" && ok "moderation and approval state per sound" || bad "status"
! said "(ERROR|WARN) +(SwordHit|Footstep)\[1\]" && ok "approved clean takes pass" || { bad "clean takes flagged"; cat $TMP/sx.txt; }
sx trim $TMP/sounds.json --out $TMP/clean
said "trim  sfx/SwordHit_2.wav: cut 44[0-9] ms before" && said "skip  sfx/UiHover_1.wav: silent" && ok "trim cuts leading silence, skips silent takes" || { bad "trim"; cat $TMP/sx.txt; }
sx check $TMP/sounds.json --root $TMP/clean --animations $SKILL/assets/examples/animations.json --vfx $SKILL/assets/Vfx.luau
! said "(ERROR|WARN) +SwordHit\[2\]" && ! said "(ERROR|WARN) +Footstep\[3\]" && ok "after trim: lag, clipping and loudness fixed" || { bad "trim did not fix"; cat $TMP/sx.txt; }
said "SwordHit\[3\] .*hits 3[0-9]{2} ms after" && said "Pickup\[1\] .*the sound lasts" && ok "after trim: build-up and length still reported (trim cuts silence, not sound)" || bad "trim hid real problems"
sx plan $TMP/sounds.json
said "SwordHit x3 \(0\.8 s\): two steel swords clashing hard, a bright ringing clang, anime, loud, .*under 0\.8 seconds" && said "10 take\(s\), 6 s of audio, about .0\.01 at .0\.0018/s\. Nothing was generated" && ok "plan: prompts with the style line, takes, price, nothing generated" || { bad "plan"; cat $TMP/sx.txt; }
python3 - "$TMP" <<'PYJ'
import json, sys
tmp = sys.argv[1]
base = json.load(open(f"{tmp}/sounds.json"))
def case(name, mutate):
    data = json.loads(json.dumps(base)); mutate(data); json.dump(data, open(f"{tmp}/{name}.json", "w"))
case("badmarker", lambda d: d["sounds"][0].__setitem__("marker", "Chop:Clang"))
case("badvfx", lambda d: d["sounds"][0].__setitem__("vfx", "Sparkles"))
case("noid", lambda d: d["sounds"][0]["variants"][0].pop("id"))
case("badpitch", lambda d: d["sounds"][0].__setitem__("pitch", [1.2, 0.8]))
case("badkey", lambda d: d["sounds"][0].__setitem__("loop", True))
case("badstatus", lambda d: d["sounds"][0]["variants"][0].__setitem__("status", "done"))
PYJ
sx check $TMP/badmarker.json --animations $SKILL/assets/examples/animations.json; said "marker Chop:Clang: 'Chop' has no 'Clang' marker" && ok "marker must exist in animations.json" || bad "bad marker"
sx check $TMP/badvfx.json --vfx $SKILL/assets/Vfx.luau; said "vfx 'Sparkles' is not a preset" && ok "vfx must be a Vfx.luau preset" || bad "bad vfx"
sx check $TMP/noid.json; said "status approved needs the uploaded 'id'" && ok "approved take needs an id" || bad "approved without id"
for c in badpitch badkey badstatus; do sx check $TMP/$c.json; [ "$(tail -n1 $TMP/sx.txt)" = 2 ] && said "manifest error" || bad "$c not rejected"; done && ok "bad pitch range, unknown key, unknown status are manifest errors (exit 2)"
$SX luau $TMP/sounds.json -o $TMP/SfxIds.luau > /dev/null
lune run $HERE/sfx_test $TMP/SfxIds.luau > $TMP/sfxrt.txt; code=$?
sed 's/^/  /' $TMP/sfxrt.txt | grep -E "FAIL|passed"
[ $code -eq 0 ] && ok "Sfx.luau: approved takes, random take and pitch, quieter repeats, marker sync with AnimationSet + Vfx" || { bad "Sfx.luau"; cat $TMP/sfxrt.txt; }

echo "textures"
python3 $SKILL/scripts/make_textures.py $TMP/textures > /dev/null
python3 - "$TMP/textures" "$SKILL/assets/textures" <<'PY' && ok "generator output matches the committed textures, 128x128 RGBA (+ 512x512 slash_4x4 sheet)" || bad "textures"
import sys
from PIL import Image, ImageChops
new, committed = sys.argv[1], sys.argv[2]
for name, size in [("glow", 128), ("star", 128), ("spark", 128), ("smoke", 128), ("ring", 128), ("slash_4x4", 512)]:
    a, b = Image.open(f"{new}/{name}.png"), Image.open(f"{committed}/{name}.png")
    assert a.size == (size, size) and a.mode == "RGBA", name
    # small tolerance: blur/resampling differ slightly between Pillow versions
    worst = max(hi for _, hi in ImageChops.difference(a, b).getextrema())
    assert worst <= 16, f"{name} differs from the committed file (max channel diff {worst})"
    assert a.getchannel("A").getextrema()[1] > 200, f"{name} is empty"
PY

echo "blender_check.py (real Blender via the bpy module; set BPY_PYTHON to a Python with bpy installed)"
if [ -n "${BPY_PYTHON:-}" ] || python3 -c "import bpy" 2>/dev/null; then
	"${BPY_PYTHON:-python3}" $HERE/blender_test.py $SKILL/scripts/blender_check.py "$TMP" > $TMP/blender.txt 2>&1; code=$?
	grep -E "^  (ok|FAIL)|passed" $TMP/blender.txt
	[ $code -eq 0 ] && ok "blender_test.py" || bad "blender_test.py"
	echo "model_batch.py (example manifest on generated sources: dry run, FBX, icons, resume)"
	"${BPY_PYTHON:-python3}" $HERE/model_batch_test.py $SKILL/scripts/model_batch.py $SKILL/assets/examples/models.json "$TMP" > $TMP/batch.txt 2>&1; code=$?
	grep -E "^  (ok  |FAIL) [^ ]|passed" $TMP/batch.txt
	[ $code -eq 0 ] && ok "model_batch_test.py" || { bad "model_batch_test.py"; tail -20 $TMP/batch.txt; }
	echo "anim_accept.py (R15 + R6 scene: ground contact Walk, Chop with a katana, broken variants)"
	"${BPY_PYTHON:-python3}" $HERE/anim_accept_test.py $SKILL/scripts/anim_accept.py $SKILL/assets/examples/animations.json "$TMP/accept" > $TMP/accept.txt 2>&1; code=$?
	grep -E "^  (ok  |FAIL) [^ ]|passed" $TMP/accept.txt
	[ $code -eq 0 ] && ok "anim_accept_test.py" || { bad "anim_accept_test.py"; tail -20 $TMP/accept.txt; }
	lune run $HERE/model_specs_test "$TMP/models/build/models/ModelSpecs.luau" > $TMP/specs.txt; code=$?
	sed 's/^/  /' $TMP/specs.txt | grep -E "FAIL|passed"
	[ $code -eq 0 ] && ok "ModelSpecs.luau applies pivots and grip Attachments (Lune, real API database)" || { bad "ModelSpecs.luau"; cat $TMP/specs.txt; }
else
	echo "  skipped: no Python with bpy (pip install bpy needs the Python version Blender ships for)"
fi

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
