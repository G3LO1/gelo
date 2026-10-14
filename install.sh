#!/usr/bin/env bash
# Installs the roblox-studio skills into a project's .claude/skills/ folder (or ~/.claude/skills/ with --global),
# so Claude Code picks them up there without the plugin.
#
#   bash install.sh                  -> current folder (./.claude/skills/)
#   bash install.sh /path/to/game    -> that project
#   bash install.sh --global         -> every project (~/.claude/skills/)
#
# Without a checkout:
#   curl -fsSL https://raw.githubusercontent.com/G3LO1/gelo/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/G3LO1/gelo/main/install.sh | bash -s -- --global
#
# GELO_REF picks a branch or tag to download (default main); GELO_TARBALL_URL overrides the whole URL.
set -euo pipefail

usage() {
  echo "Usage: install.sh [PROJECT_FOLDER | --global]"
  echo "Copies the roblox-studio skills into PROJECT_FOLDER/.claude/skills (default: current folder)"
  echo "or ~/.claude/skills with --global."
}

GLOBAL=0
PROJECT=""
for arg in "$@"; do
  case "$arg" in
    --global) GLOBAL=1 ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "ERROR: unknown option $arg" >&2; exit 1 ;;
    *)
      [ -z "$PROJECT" ] || { echo "ERROR: give at most one project folder" >&2; exit 1; }
      PROJECT="$arg"
      ;;
  esac
done
if [ "$GLOBAL" = 1 ] && [ -n "$PROJECT" ]; then
  echo "ERROR: use either --global or a project folder, not both" >&2
  exit 1
fi

if [ "$GLOBAL" = 1 ]; then
  TARGET="$HOME/.claude/skills"
else
  PROJECT="${PROJECT:-$PWD}"
  [ -d "$PROJECT" ] || { echo "ERROR: folder $PROJECT does not exist" >&2; exit 1; }
  TARGET="$(cd "$PROJECT" && pwd)/.claude/skills"
fi

# Skills from this checkout, or from a downloaded archive when the script was piped in.
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
SRC="$SCRIPT_DIR/plugins/roblox-studio/skills"
if [ -z "$SCRIPT_DIR" ] || [ ! -d "$SRC" ]; then
  URL="${GELO_TARBALL_URL:-https://codeload.github.com/G3LO1/gelo/tar.gz/${GELO_REF:-main}}"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  echo "Downloading $URL"
  curl -fsSL "$URL" | tar -xz -C "$TMP"
  SRC="$(find "$TMP" -mindepth 4 -maxdepth 4 -type d -path '*/plugins/roblox-studio/skills' | head -n 1)"
  [ -n "$SRC" ] || { echo "ERROR: plugins/roblox-studio/skills not found in $URL" >&2; exit 1; }
fi

mkdir -p "$TARGET"
count=0
for dir in "$SRC"/*/; do
  [ -f "$dir/SKILL.md" ] || continue
  name="$(basename "$dir")"
  # Replace only our own skills; anything else in the folder stays.
  rm -rf "${TARGET:?}/$name"
  cp -R "${dir%/}" "$TARGET/$name"
  echo "  $name"
  count=$((count + 1))
done
[ "$count" -gt 0 ] || { echo "ERROR: no skills found in $SRC" >&2; exit 1; }

echo "OK: $count skills installed in $TARGET"
echo "Restart Claude Code in that folder (or start a new session) and type e.g. /roblox-map-builder"
