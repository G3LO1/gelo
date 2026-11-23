#!/usr/bin/env bash
# Tests for the roblox-launch-kit store asset checker on generated good/bad store folders (with
# in-game shots), and the repeatable scenes (scene_spec.py, ShotDirector.luau).
# Needs: python3 + pillow, lune. Run from the repo root: bash tests/roblox-launch-kit/run.sh
set -u
CHECK=plugins/roblox-studio/skills/roblox-launch-kit/scripts/check_store_assets.py
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; }
expect() { grep -qE "$2" "$TMP/$1.txt" && ok "$1: $3" || { bad "$1: $3"; }; }

python3 tests/roblox-launch-kit/make_assets.py "$TMP" > /dev/null || { echo "could not generate assets"; exit 1; }

echo "good store folder"
python3 $CHECK "$TMP/good" --strict --preview "$TMP/good.html" > "$TMP/good.txt"
[ $? -eq 0 ] && ok "no errors or warnings (--strict)" || { bad "good folder reported problems:"; cat "$TMP/good.txt"; }
grep -q "hook: 'Undead Eats is a co-op" "$TMP/good.txt" && ok "hook = first 160 characters" || bad "hook not reported"
grep -q "Thumbnails as Home tiles" "$TMP/good.html" && grep -q "data:image/jpeg;base64" "$TMP/good.html" && ok "preview HTML with embedded images" || bad "preview HTML"

echo "bad store folder"
python3 $CHECK "$TMP/bad" --preview "$TMP/bad.html" > "$TMP/bad.txt"
[ $? -eq 1 ] && ok "exit 1 on errors" || bad "exit code"
expect bad "ERROR icon.png: icon must be square" "non-square icon"
expect bad "WARN  icon.png: icon is 300x200" "small icon"
expect bad "WARN  icon.png: low contrast" "flat icon"
expect bad "ERROR thumbnail 1 .*MB; Home page thumbnails must be under 3 MB" "thumbnail over 3 MB"
expect bad "WARN  thumbnail 2 .*not 16:9" "not 16:9"
expect bad "WARN  thumbnail 2 .*1920x1080" "low resolution"
expect bad "WARN  thumbnail 3 .*bottom 15%" "busy bottom edge"
expect bad "WARN  thumbnails: thumbnails 4 and 5 look almost the same" "near-duplicates"
grep -c "look almost the same" "$TMP/bad.txt" | grep -qx 1 && ok "bad: duplicates reported once per group" || bad "bad: duplicate grouping"
expect bad "ERROR thumbnail 6 .*unsupported format .webp" "unsupported format"
expect bad "WARN  title: repeated word\(s\) obby" "repeated words"
expect bad "WARN  title: 4 emojis" "too many emojis"
expect bad "WARN  title: mostly capital" "all caps"
expect bad "WARN  title: 'FREE ROBUX'" "giveaway bait in name"
expect bad "ERROR description: [0-9]+ characters, limit is 1000" "description over 1000"
expect bad "WARN  description: the first 160" "hook without the name"
expect bad "WARN  description: hashtags" "hashtags"
expect bad "WARN  description: lists controls" "control list"
grep -q "thumbnail 3" "$TMP/good.txt" && bad "good folder has a thumbnail 3?" || ok "only real files counted"
grep -c "bottom 15%" "$TMP/bad.txt" | grep -qx 1 && ok "busy-bottom heuristic fires only on the busy thumbnail" || { bad "busy-bottom heuristic:"; grep "bottom 15%" "$TMP/bad.txt"; }

echo "in-game shots vs thumbnails"
grep -qE "thumbnail 1 vs shot 1-truck.png: similarity (0\.[89]|1\.0)" "$TMP/good.txt" && grep -qE "thumbnail 2 vs shot 2-night.png: similarity" "$TMP/good.txt" \
	&& ok "good: thumbnails made from their shots are recognised (high similarity, no warnings)" || { bad "good pairs:"; grep "vs shot" "$TMP/good.txt"; }
grep -q "In-game shot vs thumbnail" "$TMP/good.html" && grep -q "At the sizes players see them" "$TMP/good.html" && grep -q "384x216 Home tile, desktop" "$TMP/good.html" && grep -q "160x90 smallest lists" "$TMP/good.html" \
	&& ok "preview: shot next to thumbnail, and every thumbnail at tile sizes" || bad "preview sections"
expect bad "WARN  thumbnail 3 vs shot 3-busy.png: the thumbnail looks unlike its in-game shot" "thumbnail that no longer shows the game"
expect bad "WARN  thumbnail 2 vs shot 2-square.png: the thumbnail \(1000x1000\) has another shape than its shot \(1920x1080\)" "thumbnail stretched from its shot"
expect bad "WARN  thumbnail 4 vs shot 4-same.png: blue line down the left edge" "Studio focus outline on the shot"
expect bad "WARN  thumbnail 4 vs shot 4-same.png: the shot is 1440x1080, not 16:9" "shot not 16:9"
expect bad "INFO  shots: 9-orphan.png has no thumbnail" "unpaired shot"
grep -c "blue line" "$TMP/bad.txt" | grep -qx 1 && ! grep -q "WARN  thumbnail 1 vs" "$TMP/bad.txt" && ok "no false alarms on the other shots" || bad "false alarms on shots"

echo "repeatable scenes (scene_spec.py + ShotDirector.luau)"
SC="python3 plugins/roblox-studio/skills/roblox-launch-kit/scripts/scene_spec.py"
EX=plugins/roblox-studio/skills/roblox-launch-kit/assets/examples/scenes
AV=plugins/roblox-studio/skills/roblox-animation-vfx
$SC check $EX/*.json --animations $AV/assets/examples/animations.json --sounds $AV/assets/examples/sounds.json --vfx $AV/assets/Vfx.luau > "$TMP/scene.txt"
[ $? -eq 0 ] && grep -q "scene SwordClash: 7.38 s, 3 camera key(s), 2 actor(s), 7 event(s), 3 shot(s)" "$TMP/scene.txt" && grep -q "^0 error(s)" "$TMP/scene.txt" \
	&& ok "example scene: valid, names match animations.json, sounds.json and Vfx.luau" || { bad "example scene:"; cat "$TMP/scene.txt"; }
$SC timeline $EX/SwordClash.json > "$TMP/timeline.txt"
grep -q "| 2.5 | 4.62 | SHOT | Clash (test, thumbnail, trailer) |" "$TMP/timeline.txt" && grep -q "130 BPM, 4 bars" "$TMP/timeline.txt" && ok "timeline: shot list on the beat grid (bar 2.5 = 4.62 s at 130 BPM)" || { bad "timeline"; cat "$TMP/timeline.txt"; }
python3 - "$EX/SwordClash.json" "$TMP" <<'PYJ'
import json, sys
base, tmp = json.load(open(sys.argv[1])), sys.argv[2]
def case(name, mutate):
    data = json.loads(json.dumps(base)); mutate(data); json.dump(data, open(f"{tmp}/scene_{name}.json", "w"))
case("late", lambda d: d["events"].append({"at": {"bar": 6}, "kind": "vfx", "name": "Slash"}))
case("names", lambda d: (d["events"].append({"at": 1, "kind": "animation", "actor": "Hero", "name": "Dance"}), d["events"].append({"at": 1, "kind": "sfx", "name": "Boom"}), d["events"].append({"at": 1, "kind": "vfx", "name": "Fireworks"})))
case("actor", lambda d: d["events"].append({"at": 1, "kind": "move", "actor": "Ghost", "to": [0, 0, 0]}))
case("nobpm", lambda d: d.pop("bpm"))
case("order", lambda d: d["camera"].reverse())
case("lazy", lambda d: (d["ready"].update(preload=[], rehearse=False), d.pop("shots")))
PYJ
$SC check "$TMP/scene_late.json" > "$TMP/s.txt"; grep -q "ERROR SwordClash: event at 11.08 s is outside the scene" "$TMP/s.txt" && ok "events after the end are errors" || { bad "late event"; cat "$TMP/s.txt"; }
$SC check "$TMP/scene_names.json" --animations $AV/assets/examples/animations.json --sounds $AV/assets/examples/sounds.json --vfx $AV/assets/Vfx.luau > "$TMP/s.txt"
grep -q "animation 'Dance' is not in animations.json" "$TMP/s.txt" && grep -q "sound 'Boom' is not in sounds.json" "$TMP/s.txt" && grep -q "vfx 'Fireworks' is not a Vfx preset" "$TMP/s.txt" && ok "animation, sound and vfx names checked against their manifests" || { bad "names"; cat "$TMP/s.txt"; }
rejected=0; for c in actor nobpm order; do $SC check "$TMP/scene_$c.json" > "$TMP/s.txt"; [ $? -eq 2 ] && rejected=$((rejected+1)); done
[ $rejected -eq 3 ] && ok "unknown actor, bars without bpm, camera keys out of order: scene errors (exit 2)" || bad "only $rejected of 3 broken scenes rejected"
$SC check "$TMP/scene_lazy.json" > "$TMP/s.txt"; grep -q "WARN  SwordClash: no shots" "$TMP/s.txt" && grep -q "ready.preload is empty" "$TMP/s.txt" && grep -q "ready.rehearse is off" "$TMP/s.txt" && ok "no shots, nothing preloaded, no rehearsal: warned" || { bad "lazy scene"; cat "$TMP/s.txt"; }
$SC luau $EX/*.json -o "$TMP/Scenes.luau" > /dev/null
lune run tests/roblox-launch-kit/director_test "$TMP/Scenes.luau" > "$TMP/director.txt"; code=$?
sed 's/^/  /' "$TMP/director.txt" | grep -E "FAIL|passed"
[ $code -eq 0 ] && ok "ShotDirector.luau: camera path, events on time, silent rehearsal, shots, reset, same frames every run" || { bad "ShotDirector.luau"; cat "$TMP/director.txt"; }

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
