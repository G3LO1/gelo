#!/usr/bin/env bash
# install.sh (and install.ps1 when pwsh is on PATH): local checkout, piped-in download, --global, bad arguments.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILLS="$ROOT/plugins/roblox-studio/skills"
WORK="$(mktemp -d)"
SERVER_PID=""
cleanup() {
  [ -z "$SERVER_PID" ] || kill "$SERVER_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

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

# Archives served over HTTP, laid out like GitHub's codeload (one top folder).
mkdir -p "$WORK/stage/gelo-main/plugins" "$WORK/www"
cp -R "$ROOT/plugins/roblox-studio" "$WORK/stage/gelo-main/plugins/"
tar -czf "$WORK/www/gelo.tar.gz" -C "$WORK/stage" gelo-main
(cd "$WORK/stage" && python3 -c "import shutil; shutil.make_archive('$WORK/www/gelo', 'zip', '.', 'gelo-main')")
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK/www" >/dev/null 2>&1 &
SERVER_PID=$!
for _ in $(seq 50); do
  curl -sf -o /dev/null "http://127.0.0.1:$PORT/gelo.tar.gz" && break
  sleep 0.1
done

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

P="$WORK/sh-pipe"; mkdir -p "$P"; prepare_project "$P"
(cd "$WORK" && GELO_TARBALL_URL="http://127.0.0.1:$PORT/gelo.tar.gz" bash -s -- "$P" <"$ROOT/install.sh" >/dev/null)
expect_installed "$P/.claude/skills"; expect_untouched_neighbours "$P"
echo "ok   piped in (curl | bash), downloads the archive"

! bash "$ROOT/install.sh" "$WORK/missing" 2>/dev/null || fail "missing folder accepted"
! bash "$ROOT/install.sh" --global "$WORK" 2>/dev/null || fail "--global with a folder accepted"
! bash "$ROOT/install.sh" --bogus 2>/dev/null || fail "unknown option accepted"
[ ! -e "$WORK/missing" ] || fail "missing folder was created"
echo "ok   bad arguments rejected"

if command -v pwsh >/dev/null 2>&1; then
  echo "== install.ps1 ($(pwsh -NoProfile -c '$PSVersionTable.PSVersion.ToString()'))"
  PS="pwsh -NoProfile -NonInteractive"

  P="$WORK/ps-cwd"; mkdir -p "$P"; prepare_project "$P"
  (cd "$P" && $PS -File "$ROOT/install.ps1" >/dev/null)
  expect_installed "$P/.claude/skills"; expect_untouched_neighbours "$P"
  echo "ok   current folder"

  P="$WORK/ps-arg"; mkdir -p "$P"
  $PS -File "$ROOT/install.ps1" -Project "$P" >/dev/null
  expect_installed "$P/.claude/skills"
  echo "ok   -Project"

  H="$WORK/ps-home"; mkdir -p "$H"
  HOME="$H" $PS -File "$ROOT/install.ps1" -Global >/dev/null
  expect_installed "$H/.claude/skills"
  echo "ok   -Global"

  P="$WORK/ps-pipe"; mkdir -p "$P"; prepare_project "$P"
  (cd "$P" && GELO_ZIP_URL="http://127.0.0.1:$PORT/gelo.zip" $PS -Command "Get-Content -Raw '$ROOT/install.ps1' | Invoke-Expression" >/dev/null)
  expect_installed "$P/.claude/skills"; expect_untouched_neighbours "$P"
  echo "ok   piped in (irm | iex), downloads the archive"

  P="$WORK/ps-sb"; mkdir -p "$P"
  GELO_ZIP_URL="http://127.0.0.1:$PORT/gelo.zip" $PS -Command "& ([scriptblock]::Create((Get-Content -Raw '$ROOT/install.ps1'))) -Project '$P'" >/dev/null
  expect_installed "$P/.claude/skills"
  echo "ok   scriptblock with arguments"

  ! $PS -File "$ROOT/install.ps1" -Project "$WORK/missing" >/dev/null 2>&1 || fail "ps1: missing folder accepted"
  ! $PS -File "$ROOT/install.ps1" -Global -Project "$WORK" >/dev/null 2>&1 || fail "ps1: -Global with -Project accepted"
  echo "ok   bad arguments rejected"
else
  echo "== install.ps1 skipped (pwsh not found)"
fi

echo "All install tests passed."
