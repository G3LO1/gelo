#!/usr/bin/env bash
# install.sh (and install.ps1 when pwsh is on PATH): current/other folder, --global, rerun, bad arguments.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILLS="$ROOT/plugins/roblox-studio/skills"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

expect_installed() { # <skills folder>
  local dest="$1" n=0
  for dir in "$SKILLS"/*/; do
    name="$(basename "$dir")"
    diff -r "${dir%/}" "$dest/$name" >/dev/null || fail "$dest/$name differs from $dir"
    n=$((n + 1))
  done
  [ "$n" -gt 0 ] || fail "no skills in $SKILLS"
}

prepare_project() { # <folder>: a project that already has someone else's skill and a stale file in ours
  mkdir -p "$1/.claude/skills/my-own-skill" "$1/.claude/skills/roblox-map-builder"
  echo keep >"$1/.claude/skills/my-own-skill/SKILL.md"
  echo stale >"$1/.claude/skills/roblox-map-builder/old.md"
}

expect_untouched_neighbours() { # <folder>
  [ "$(cat "$1/.claude/skills/my-own-skill/SKILL.md")" = keep ] || fail "other skill in $1 was changed"
  [ ! -e "$1/.claude/skills/roblox-map-builder/old.md" ] || fail "stale file in $1 not removed"
}

echo "== install.sh"

P="$WORK/sh-cwd"; mkdir -p "$P"; prepare_project "$P"
(cd "$P" && bash "$ROOT/install.sh" >/dev/null)
expect_installed "$P/.claude/skills"; expect_untouched_neighbours "$P"
(cd "$P" && bash "$ROOT/install.sh" >/dev/null)   # second run replaces cleanly
expect_installed "$P/.claude/skills"
echo "ok   current folder, rerun"

P="$WORK/sh-arg"; mkdir -p "$P"
bash "$ROOT/install.sh" "$P" >/dev/null
expect_installed "$P/.claude/skills"
echo "ok   project folder argument"

H="$WORK/sh-home"; mkdir -p "$H"
HOME="$H" bash "$ROOT/install.sh" --global >/dev/null
expect_installed "$H/.claude/skills"
echo "ok   --global"

! bash "$ROOT/install.sh" "$WORK/missing" 2>/dev/null || fail "missing folder accepted"
! bash "$ROOT/install.sh" --global "$WORK" 2>/dev/null || fail "--global with a folder accepted"
! bash "$ROOT/install.sh" --bogus 2>/dev/null || fail "unknown option accepted"
[ ! -e "$WORK/missing" ] || fail "missing folder was created"
P="$WORK/sh-pipe"; mkdir -p "$P"
! (cd "$P" && bash -s <"$ROOT/install.sh" 2>"$WORK/err") || fail "piped-in run (no clone) accepted"
grep -q "git clone" "$WORK/err" || fail "piped-in run does not say to clone the repo"
[ ! -e "$P/.claude" ] || fail "piped-in run created .claude"
echo "ok   bad arguments and runs outside a clone rejected"

if command -v pwsh >/dev/null 2>&1; then
  echo "== install.ps1 ($(pwsh -NoProfile -c '$PSVersionTable.PSVersion.ToString()'))"
  PS="pwsh -NoProfile -NonInteractive"

  P="$WORK/ps-cwd"; mkdir -p "$P"; prepare_project "$P"
  (cd "$P" && $PS -File "$ROOT/install.ps1" >/dev/null)
  expect_installed "$P/.claude/skills"; expect_untouched_neighbours "$P"
  (cd "$P" && $PS -File "$ROOT/install.ps1" >/dev/null)
  expect_installed "$P/.claude/skills"
  echo "ok   current folder, rerun"

  P="$WORK/ps-arg"; mkdir -p "$P"
  $PS -File "$ROOT/install.ps1" -Project "$P" >/dev/null
  expect_installed "$P/.claude/skills"
  echo "ok   -Project"

  H="$WORK/ps-home"; mkdir -p "$H"
  HOME="$H" $PS -File "$ROOT/install.ps1" -Global >/dev/null
  expect_installed "$H/.claude/skills"
  echo "ok   -Global"

  ! $PS -File "$ROOT/install.ps1" -Project "$WORK/missing" >/dev/null 2>&1 || fail "ps1: missing folder accepted"
  ! $PS -File "$ROOT/install.ps1" -Global -Project "$WORK" >/dev/null 2>&1 || fail "ps1: -Global with -Project accepted"
  P="$WORK/ps-pipe"; mkdir -p "$P"
  ! (cd "$P" && $PS -Command "Get-Content -Raw '$ROOT/install.ps1' | Invoke-Expression" >"$WORK/err" 2>&1) \
    || fail "ps1: piped-in run (no clone) accepted"
  grep -q "git clone" "$WORK/err" || fail "ps1: piped-in run does not say to clone the repo"
  [ ! -e "$P/.claude" ] || fail "ps1: piped-in run created .claude"
  echo "ok   bad arguments and runs outside a clone rejected"
else
  echo "== install.ps1 skipped (pwsh not found)"
fi

echo "All install tests passed."
