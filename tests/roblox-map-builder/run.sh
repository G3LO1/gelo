#!/usr/bin/env bash
# Tests for the roblox-map-builder skill: validate_map.luau rules on a clean and a bad map
# (exact findings), the validate_place.luau CLI, Scatter.luau and LightingPresets.luau
# against Roblox's API database.
# Needs: lune. Run from the repo root: bash tests/roblox-map-builder/run.sh
set -u
SKILL=plugins/roblox-studio/skills/roblox-map-builder/scripts
HERE=tests/roblox-map-builder
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; }

echo "map_test.luau"
lune run $HERE/map_test $TMP | tee $TMP/out.txt | grep -E "^(  FAIL|    )|passed"
[ "${PIPESTATUS[0]}" -eq 0 ] && ok "validator, Scatter, LightingPresets" || bad "map_test.luau"

echo "validate_place.luau CLI"
lune run $SKILL/validate_place.luau $TMP/clean.rbxl --fail-on high > $TMP/clean.txt \
	&& ok "clean map exits 0" || { bad "clean map exit code"; cat $TMP/clean.txt; }
grep -q "SKIPPED" $TMP/clean.txt && ok "raycast and pathfinding checks are reported as skipped under Lune" || bad "skipped note missing"
lune run $SKILL/validate_place.luau $TMP/bad.rbxl --fail-on high --json $TMP/bad.json > $TMP/bad.txt
[ $? -eq 1 ] && ok "bad map exits 1 with --fail-on high" || bad "bad map exit code"
grep -q "HIGH SPAWN-BLOCKED" $TMP/bad.txt && ok "text report lists the blocked spawn" || bad "text report"
python3 -c "import json,sys; r=json.load(open('$TMP/bad.json')); sys.exit(0 if any(f['rule']=='Z-FIGHTING' for f in r['findings']) else 1)" \
	&& ok "JSON report written" || bad "JSON report"
lune run $SKILL/validate_place.luau $TMP/bad.rbxl --fail-on none > /dev/null && ok "--fail-on none always exits 0" || bad "--fail-on none"

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
