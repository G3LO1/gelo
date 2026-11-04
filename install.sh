#!/usr/bin/env bash
# Installs the roblox-studio skills where your coding agent looks for them, without the Claude Code plugin.
#
#   bash install.sh                  -> current folder, Claude Code (./.claude/skills/)
#   bash install.sh /path/to/game    -> that project
#   bash install.sh --global         -> every project (~/.claude/skills/)
#   bash install.sh --target codex   -> OpenAI Codex (./.agents/skills/, global ~/.agents/skills/)
#   bash install.sh --target antigravity -> Google Antigravity (./.agents/skills/, global ~/.gemini/config/skills/)
#   bash install.sh --target all     -> Claude Code + Codex + Antigravity
#
# Without a checkout:
#   curl -fsSL https://raw.githubusercontent.com/G3LO1/gelo/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/G3LO1/gelo/main/install.sh | bash -s -- --global
#
# GELO_REF picks a branch or tag to download (default main); GELO_TARBALL_URL overrides the whole URL.
set -euo pipefail

usage() {
  echo "Usage: install.sh [--target claude|codex|antigravity|all] [PROJECT_FOLDER | --global]"
  echo "Copies the roblox-studio skills into the agent's skills folder:"
  echo "  claude       PROJECT_FOLDER/.claude/skills        (--global: ~/.claude/skills)   [default]"
  echo "  codex        PROJECT_FOLDER/.agents/skills        (--global: ~/.agents/skills)"
  echo "  antigravity  PROJECT_FOLDER/.agents/skills        (--global: ~/.gemini/config/skills)"
  echo "  all          all of the above"
  echo "PROJECT_FOLDER defaults to the current folder."
}

GLOBAL=0
PROJECT=""
AGENT="claude"
EXPECT_TARGET=0
for arg in "$@"; do
  if [ "$EXPECT_TARGET" = 1 ]; then AGENT="$arg"; EXPECT_TARGET=0; continue; fi
  case "$arg" in
    --global) GLOBAL=1 ;;
    --target) EXPECT_TARGET=1 ;;
    --target=*) AGENT="${arg#--target=}" ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "ERROR: unknown option $arg" >&2; exit 1 ;;
    *)
      [ -z "$PROJECT" ] || { echo "ERROR: give at most one project folder" >&2; exit 1; }
      PROJECT="$arg"
      ;;
  esac
done
[ "$EXPECT_TARGET" = 0 ] || { echo "ERROR: --target needs a value (claude, codex, antigravity or all)" >&2; exit 1; }
if [ "$GLOBAL" = 1 ] && [ -n "$PROJECT" ]; then
  echo "ERROR: use either --global or a project folder, not both" >&2
  exit 1
fi

# Skills folders for the chosen agent(s). Codex and Antigravity share .agents/skills in a project.
case "$AGENT" in
  claude) REL=(".claude/skills"); GLOBAL_DIRS=("$HOME/.claude/skills") ;;
  codex) REL=(".agents/skills"); GLOBAL_DIRS=("$HOME/.agents/skills") ;;
  antigravity) REL=(".agents/skills"); GLOBAL_DIRS=("$HOME/.gemini/config/skills") ;;
  all) REL=(".claude/skills" ".agents/skills"); GLOBAL_DIRS=("$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.gemini/config/skills") ;;
  *) echo "ERROR: unknown target $AGENT (use claude, codex, antigravity or all)" >&2; exit 1 ;;
esac

TARGETS=()
if [ "$GLOBAL" = 1 ]; then
  TARGETS=("${GLOBAL_DIRS[@]}")
else
  PROJECT="${PROJECT:-$PWD}"
  [ -d "$PROJECT" ] || { echo "ERROR: folder $PROJECT does not exist" >&2; exit 1; }
  PROJECT="$(cd "$PROJECT" && pwd)"
  for r in "${REL[@]}"; do TARGETS+=("$PROJECT/$r"); done
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

count=0
for TARGET in "${TARGETS[@]}"; do
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
done

case "$AGENT" in
  claude) echo "Restart Claude Code in that folder (or start a new session) and type e.g. /roblox-map-builder" ;;
  codex) echo "Restart Codex in that folder, then type /skills or \$roblox-map-builder (it also picks skills by itself)" ;;
  antigravity) echo "Restart Antigravity (or reload the workspace); it picks the skills by their description" ;;
  all) echo "Restart your agent(s) in that folder. Claude Code: /roblox-map-builder, Codex: \$roblox-map-builder, Antigravity: automatic" ;;
esac
