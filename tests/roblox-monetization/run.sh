#!/usr/bin/env bash
# Tests for roblox-monetization: monetize.py against a mock Open Cloud server (create/update/adopt,
# icons, secrets, retries), then the generated Monetization.luau + MonetizationService + ShopController
# running on the codegen template under Lune, plus StyLua on the generated module.
# Needs: python3 + pillow, lune (stylua optional). Run from the repo root: bash tests/roblox-monetization/run.sh
set -u
SKILL=plugins/roblox-studio/skills/roblox-monetization
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
status=0

echo "== monetize.py vs mock Open Cloud"
python3 tests/roblox-monetization/test_sync.py "$SKILL/scripts/monetize.py" "$SKILL/assets/monetization.example.json" "$TMP" || status=1

if [ ! -f "$TMP/Monetization.luau" ]; then
	echo "no Monetization.luau generated: skipping the Luau tests"
	exit 1
fi

if command -v stylua >/dev/null 2>&1; then
	echo "== stylua --check generated Monetization.luau"
	stylua --check --config-path plugins/roblox-studio/skills/roblox-luau-codegen/assets/template/stylua.toml \
		"$TMP/Monetization.luau" && echo "  ok   generated module is StyLua-formatted" || status=1
fi

echo "== runtime (Lune)"
lune run tests/roblox-monetization/run "$TMP" || status=1

exit $status
