#!/usr/bin/env bash
# Tests for the roblox-monetization-designer checker and Luau catalog generator.
# Needs: python3. Run from the repo root: bash tests/roblox-monetization-designer/run.sh
set -u
SKILL=plugins/roblox-studio/skills/roblox-monetization-designer
CHECK=$SKILL/scripts/monetization_check.py
HERE=tests/roblox-monetization-designer
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; }
expect() { grep -qE "$1" "$TMP/bad.txt" && ok "bad spec: $2" || bad "bad spec: $2"; }

echo "example spec"
python3 $CHECK $SKILL/assets/examples/monetization-example.json -o $TMP/Products.luau > $TMP/good.txt
[ $? -eq 0 ] && grep -q "0 error(s), 0 warning(s)" $TMP/good.txt && ok "example: no errors or warnings" || { bad "example spec:"; cat $TMP/good.txt; }
grep -q "^info: revenue: 60 payers x 2 purchases/month x 217 R\$ avg" $TMP/good.txt && ok "revenue scenario" || bad "revenue scenario"
grep -q 'DoubleCoins = { Id = 1001, Name = "2x Coins", DefaultPrice = 299 },' $TMP/Products.luau \
	&& grep -q 'CoinsSmall = { Id = 2001, Name = "1,000 Coins", DefaultPrice = 49, Grants = { Coins = 1000 } },' $TMP/Products.luau \
	&& grep -q "Enum.InfoType.GamePass else Enum.InfoType.Product" $TMP/Products.luau \
	&& grep -q "^return Products$" $TMP/Products.luau && ok "generated Luau module" || { bad "generated module:"; cat $TMP/Products.luau; }

echo "bad spec"
python3 $CHECK $HERE/bad.json -o $TMP/Never.luau > $TMP/bad.txt
[ $? -eq 1 ] && ok "exit 1 on errors" || bad "exit code"
[ ! -e $TMP/Never.luau ] && ok "no module written while there are errors" || bad "module written despite errors"
expect "warning: currencies\[0\] Coins: sinks want 400%" "grind wall (sinks > faucets)"
expect "warning: currencies\[1\] Cash: sinks drain 20%" "inflation (sinks < faucets)"
expect "warning: currencies\[2\] Gems: premium currency with no free faucet" "no free premium path"
expect "error: currencies\[3\] Dust: soft currency without a faucet" "unearnable soft currency"
expect "error: currencies\[4\] Bad Name: id must be a Luau identifier" "invalid currency id"
expect "error: products\[0\] Sword: gates a core feature but has no 'free_path'" "core feature behind paywall"
expect "warning: products\[0\] Sword: sells power in a PvP game" "pay-to-win"
expect "warning: products\[0\] Sword: passes are permanent perks" "pass that grants consumables"
expect "error: products\[1\] Crate: paid random item without disclosed odds" "undisclosed odds"
expect "warning: products\[1\] Crate: paid random item: check PolicyService" "policy check"
expect "warning: products\[1\] Crate: countdown/limited-time pressure" "dark pattern for all ages"
expect "error: products\[2\] Crate: duplicate id" "duplicate id"
expect "error: products\[5\] Empty: developer product without 'grants'" "product grants nothing"
expect "error: products\[6\] Ghosty: grants unknown currency 'Rubies'" "unknown currency in grants"
expect "error: products\[7\] Free: price must be a whole number" "price 0"
expect "error: products\[8\] NoAsset: no asset id yet" "missing asset id"
expect "error: products\[9\] Odd: type must be one of" "unknown type"
expect "error: products\[10\] Sub: no asset id yet" "subscription id must be EXP-"
expect "warning: goals\[0\] First: first goal takes 30.0 min" "slow first goal"
expect "warning: goals\[1\] Wall: 40 h of earning" "grind wall goal"
expect "error: goals\[2\] Ghost: unknown currency 'Nope'" "goal with unknown currency"
expect "warning: packs Gems: Gems12 \(1000 R\\$\) gives 0.01 Gems/R\\$, worse than Gems10" "worse value in bigger pack"
expect "warning: revenue: payer_conversion 20% is optimistic" "optimistic conversion"
grep -q "packs Rubies" $TMP/bad.txt && bad "unknown currency leaked into the pack ladder" || ok "ladder ignores unknown currencies"

echo "--allow-todo"
python3 $CHECK $HERE/bad.json --allow-todo > $TMP/todo.txt
grep -q "^info: products\[8\] NoAsset: no asset id yet" $TMP/todo.txt && ok "missing asset id is info with --allow-todo" || bad "--allow-todo"

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
