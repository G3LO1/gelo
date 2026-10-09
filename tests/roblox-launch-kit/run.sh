#!/usr/bin/env bash
# Tests for the roblox-launch-kit store asset checker on generated good/bad store folders.
# Needs: python3 + pillow. Run from the repo root: bash tests/roblox-launch-kit/run.sh
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

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
