#!/usr/bin/env bash
# Installs the roblox-studio skills into a project's .claude/skills/ folder (or ~/.claude/skills/ with --global),
# so Claude Code picks them up there without the plugin. Run it from a clone of the repo:
#
#   bash install.sh                  -> current folder (./.claude/skills/)
#   bash install.sh /path/to/game    -> that project
#   bash install.sh --global         -> every project (~/.claude/skills/)
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

SRC=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plugins/roblox-studio/skills"
fi
if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
  echo "ERROR: run install.sh from a clone of the repo:" >&2
  echo "  git clone https://github.com/G3LO1/gelo.git && bash gelo/install.sh /path/to/game" >&2
  exit 1
fi

if [ "$GLOBAL" = 1 ]; then
  TARGET="$HOME/.claude/skills"
else
  PROJECT="${PROJECT:-$PWD}"
  [ -d "$PROJECT" ] || { echo "ERROR: folder $PROJECT does not exist" >&2; exit 1; }
  TARGET="$(cd "$PROJECT" && pwd)/.claude/skills"
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
