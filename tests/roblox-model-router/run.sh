#!/usr/bin/env bash
# Tests for roblox-model-router: detect_models.py on fake home/project folders, agent and skill frontmatter.
# Needs: python3. Run from the repo root: bash tests/roblox-model-router/run.sh
set -u
PLUGIN=plugins/roblox-studio
DETECT=$PLUGIN/skills/roblox-model-router/scripts/detect_models.py
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; }
# run <home> <project> <host> [VAR=value...] -> JSON in $TMP/out.json
run() {
  local h="$1" p="$2" host="$3"; shift 3
  env -i PATH="$PATH" HOME="$h" "$@" python3 $DETECT --host "$host" --project "$p" --json > "$TMP/out.json" 2>/dev/null
}
q() { python3 -c "import json,sys; d=json.load(open('$TMP/out.json')); print(eval(sys.argv[1]))" "$1"; }
check() { [ "$(q "$1")" = "$2" ] && ok "$3" || bad "$3 (got: $(q "$1"))"; }

echo "agents"
for pair in roblox-scout:haiku roblox-builder:sonnet roblox-reviewer:opus; do
	name=${pair%%:*}; model=${pair##*:}; f=$PLUGIN/agents/$name.md
	head -1 $f | grep -qx -- '---' && grep -qx "name: $name" $f && grep -qx "model: $model" $f && grep -q '^description: ' $f && ok "$name: frontmatter, model $model" || bad "$name frontmatter"
done
grep -qx "tools: Read, Grep, Glob, Bash" $PLUGIN/agents/roblox-scout.md && ! grep -qE '^tools:.*(Edit|Write)' $PLUGIN/agents/roblox-reviewer.md && ok "scout and reviewer cannot edit files" || bad "tool restrictions"
grep -q '^model:' $PLUGIN/skills/*/SKILL.md && bad "a skill sets 'model' (breaks the portable Agent Skills spec)" || ok "skills stay free of Claude-only frontmatter keys"

echo "defaults (no settings)"
H=$TMP/h0; P=$TMP/p0; mkdir -p $H $P
run $H $P claude-code
check "d['tiers']['light']['alias']+d['tiers']['standard']['alias']+d['tiers']['strong']['alias']" "haikusonnetopus" "tiers map to aliases"
check "d['tiers']['light']['allowed']" "True" "all families allowed"
check "d['settings_read']" "[]" "no settings read"

echo "restricted user (allowlist without haiku, pinned sonnet, forced subagent model)"
H=$TMP/h1; P=$TMP/p1; mkdir -p $H/.claude $P/.claude
echo '{"model":"opus","availableModels":["sonnet","opus"],"env":{"ANTHROPIC_DEFAULT_SONNET_MODEL":"claude-sonnet-4-5"}}' > $H/.claude/settings.json
echo '{"deniedModels":["opus"]}' > $P/.claude/settings.local.json
run $H $P claude-code CLAUDE_CODE_SUBAGENT_MODEL=haiku CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1
check "d['settings_read']" "['user', 'local']" "user and local settings merged"
check "d['tiers']['light']['allowed']" "False" "haiku blocked by allowlist"
check "d['tiers']['strong']['allowed']" "False" "opus blocked by deniedModels"
check "d['tiers']['standard']['pinned_to']" "claude-sonnet-4-5" "pinned sonnet from settings env"
check "d['subagent_model_forced']" "True" "forced subagent model detected"
check "any('no effect' in w for w in d['warnings'])" "True" "warns that routing is ineffective when forced"
check "d['main_model']" "opus" "main model"

echo "project overrides user; process env overrides settings env"
H=$TMP/h2; P=$TMP/p2; mkdir -p $H/.claude $P/.claude
echo '{"env":{"ANTHROPIC_DEFAULT_HAIKU_MODEL":"from-user"}}' > $H/.claude/settings.json
echo '{"env":{"ANTHROPIC_DEFAULT_HAIKU_MODEL":"from-project"}}' > $P/.claude/settings.json
run $H $P claude-code
check "d['tiers']['light']['pinned_to']" "from-project" "project settings beat user settings"
run $H $P claude-code ANTHROPIC_DEFAULT_HAIKU_MODEL=from-env
check "d['tiers']['light']['pinned_to']" "from-env" "environment beats settings"

echo "codex"
H=$TMP/h3; P=$TMP/p3; mkdir -p $H/.codex $P/.codex/agents
printf 'model = "some-model"\napproval_policy = "on-request"\n\n[profiles.fast]\nmodel = "other"\n' > $H/.codex/config.toml
run $H $P codex
check "d['host']+':'+d['main_model']" "codex:some-model" "reads top-level model only"
check "d['project_has_custom_agents_dir']" "True" "sees .codex/agents"
check "len(d['docs_to_check'])>0 and d['tiers']['light']['alias'] is None" "True" "no invented model names; docs listed"

echo "antigravity"
H=$TMP/h4; P=$TMP/p4; mkdir -p $H/.gemini/antigravity $P/.agent
run $H $P antigravity
check "d['host']+str(d['global_dir_found'])+str(d['project_agent_dir_found'])" "antigravityTrueTrue" "detects folders"
check "d['tiers']['strong']['alias'] is None" "True" "no invented model names"

echo "host auto-detection"
H=$TMP/h5; P=$TMP/p5; mkdir -p $H/.codex $P
touch $H/.codex/config.toml
env -i PATH="$PATH" HOME="$H" python3 $DETECT --project $P --json 2>/dev/null > $TMP/out.json
check "d['host']" "codex" "codex config found"
env -i PATH="$PATH" HOME="$H" CLAUDECODE=1 python3 $DETECT --project $P --json 2>/dev/null > $TMP/out.json
check "d['host']" "claude-code" "CLAUDECODE wins"

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
