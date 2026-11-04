#!/usr/bin/env bash
# Tests for roblox-bringforth: make_model.py (GLB structure, preview), bringforth.py against a mock
# Open Cloud Assets API (check, upload, operations, versions, grant, key introspection, secrets), the
# local feed and the Studio plugin on Lune; plus the GLBs in real Blender when bpy is installed
# (BPY_PYTHON=/path/to/python-with-bpy). Needs python3 + pillow, lune. Run from the repo root.
set -u -o pipefail
SKILL=plugins/roblox-studio/skills/roblox-bringforth
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
status=0

python3 tests/roblox-bringforth/test_bringforth.py "$SKILL" "$TMP/work" "$(command -v lune || true)" || status=1

if command -v stylua >/dev/null 2>&1; then
	echo "== stylua --check BringforthPlugin.lua"
	stylua --check --config-path plugins/roblox-studio/skills/roblox-luau-codegen/assets/template/stylua.toml \
		"$SKILL/assets/BringforthPlugin.lua" && echo "  ok   Studio plugin is StyLua-formatted" || status=1
fi

PY=${BPY_PYTHON:-python3}
if "$PY" -c "import bpy" >/dev/null 2>&1; then
	echo "== GLBs in real Blender"
	mkdir -p "$TMP/blender"
	"$PY" tests/roblox-bringforth/blender_glb_test.py "$SKILL" \
		plugins/roblox-studio/skills/roblox-animation-vfx/scripts/blender_check.py "$TMP/blender" 2>&1 | grep -v "INFO" || status=1
else
	echo "bpy not available: Blender import test skipped (CI runs it)"
fi
exit $status
