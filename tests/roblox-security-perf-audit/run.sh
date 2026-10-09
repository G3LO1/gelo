#!/usr/bin/env bash
# Tests for the roblox-security-perf-audit skill: scan_luau.py rules against fixtures (exact
# findings per file), no false positives on the plugin's own template and example, and the
# place audit (in memory, from files, CLI exit codes, script dump -> scanner, XML reader).
# Needs: python3, lune. Run from the repo root: bash tests/roblox-security-perf-audit/run.sh
set -u
SKILL=plugins/roblox-studio/skills/roblox-security-perf-audit/scripts
HERE=tests/roblox-security-perf-audit
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; }

echo "scan_luau.py fixtures"
python3 $SKILL/scan_luau.py $HERE/fixtures --fail-on none --json $TMP/fixtures.json > /dev/null
if python3 $HERE/check_fixtures.py $TMP/fixtures.json $HERE/fixtures > $TMP/fixtures.txt; then
	ok "every fixture gets exactly its expected findings"
else
	bad "fixture findings differ:"; cat $TMP/fixtures.txt
fi
python3 $SKILL/scan_luau.py $HERE/fixtures > /dev/null; [ $? -eq 1 ] && ok "exit 1 on high findings" || bad "exit code on high findings"

echo "no false positives on the plugin's own code"
python3 $SKILL/scan_luau.py plugins/roblox-studio/skills/roblox-luau-codegen/assets/template/src --fail-on low > $TMP/template.txt \
	&& ok "codegen template is clean" || { bad "codegen template:"; cat $TMP/template.txt; }
python3 $SKILL/scan_luau.py examples/undead-eats/src examples/undead-eats/ui --fail-on low > $TMP/example.txt \
	&& ok "Undead Eats example is clean" || { bad "Undead Eats example:"; cat $TMP/example.txt; }

echo "place audit"
lune run $HERE/audit_test $TMP | sed 's/^/  /' | grep -E "ok|FAIL|passed" ; [ "${PIPESTATUS[0]}" -eq 0 ] && ok "audit_test.luau" || bad "audit_test.luau"
lune run $SKILL/audit_place.luau $TMP/clean.rbxl --fail-on medium > /dev/null && ok "CLI: clean place exits 0" || bad "CLI: clean place exit code"
lune run $SKILL/audit_place.luau $TMP/bad.rbxl --fail-on high --json $TMP/bad.json --dump-scripts $TMP/dump > /dev/null
[ $? -eq 1 ] && ok "CLI: bad place exits 1 with --fail-on high" || bad "CLI: bad place exit code"
python3 -c "import json,sys; r=json.load(open('$TMP/bad.json')); sys.exit(0 if any(f['rule']=='SCRIPT-SUSPICIOUS' for f in r['findings']) else 1)" \
	&& ok "CLI: JSON report written" || bad "CLI: JSON report"
[ -f $TMP/dump/Workspace/FreeCar/Engine.server.luau ] && ok "CLI: scripts dumped by path" || bad "CLI: script dump"
python3 $SKILL/scan_luau.py $TMP/dump --fail-on none | grep -q "SEC-REQUIRE-ID .*Engine.server.luau:2" \
	&& ok "dumped scripts -> scanner finds the backdoor" || bad "dumped scripts not scanned"
python3 $SKILL/scan_luau.py $TMP/bad.rbxmx --fail-on none | grep -q "SEC-REQUIRE-ID .*bad.rbxmx::FreeCar.Engine:2 *\[server\]" \
	&& ok ".rbxmx scripts are read with their class context" || bad ".rbxmx reader"

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
