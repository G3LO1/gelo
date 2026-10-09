#!/usr/bin/env bash
# Static checks for generated Luau. Usage: check.sh <project-root> [files or dirs relative to it...]
# StyLua: syntax + formatting (--check, never rewrites). Selene: lints (undefined/unused
# variables, deprecated calls, shadowing) using selene.toml in the project root.
# Exit code is non-zero if any available tool reports a problem; missing tools are skipped.
set -u
root="${1:-.}"
shift || true
targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(src)
cd "$root" || exit 2
status=0
ran=0

if command -v stylua >/dev/null 2>&1; then
	ran=1
	echo "== stylua --check ${targets[*]}"
	stylua --check "${targets[@]}" || status=1
else
	echo "stylua not installed: skipping syntax/format check (cargo install stylua --features luau, or aftman/rokit)"
fi

if command -v selene >/dev/null 2>&1; then
	ran=1
	echo "== selene ${targets[*]}"
	output=$(selene "${targets[@]}" 2>&1)
	code=$?
	echo "$output"
	if [ $code -ne 0 ]; then
		if echo "$output" | grep -qi "roblox standard library"; then
			# std = "roblox" is generated from Roblox's API dump on first run; it needs internet access.
			echo "selene could not download the Roblox API definitions: lints skipped, not a code error."
		else
			status=1
		fi
	fi
else
	echo "selene not installed: skipping lints (cargo install selene, or aftman/rokit)"
fi

[ $ran -eq 0 ] && echo "No checker available: rely on Studio Script Analysis and a playtest."
exit $status
