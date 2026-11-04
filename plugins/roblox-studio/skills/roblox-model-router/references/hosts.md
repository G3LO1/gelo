# Host notes: Claude Code, Codex, Antigravity

Starting points, not truth. Model names, config keys and delegation features change often: re-check the official docs at run time (the script prints their addresses) and ask the user what their model picker shows. Confidence is marked per line.

## Claude Code (checked against code.claude.com docs, November 2026; high confidence)
- Plugin agents live in the plugin's `agents/*.md` and are addressed as `<plugin>:<agent>`, here `roblox-studio:roblox-scout|roblox-builder|roblox-reviewer`. Frontmatter `model` accepts the aliases `haiku`, `sonnet`, `opus`, `fable`, a full model id, or `inherit`.
- An alias resolves to the newest version of that family the user's provider offers (differs by provider: Anthropic API, Bedrock, Google Cloud, Foundry, Claude Platform on AWS). If the main conversation's model is in the same family, a subagent of that family runs on the main model's exact version.
- Subagent model resolution: the Agent tool call's `model` parameter (alias only) > the agent's frontmatter > `CLAUDE_CODE_SUBAGENT_MODEL` > the main model. `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` (v2.1.257+) makes one model apply to every subagent and disables routing.
- Users can restrict models with `availableModels` / `deniedModels` / `enforceAvailableModels` (settings); a blocked alias moves to the newest permitted model of the family or falls back to the inherited model. Pins: `ANTHROPIC_DEFAULT_{HAIKU,SONNET,OPUS,FABLE}_MODEL`.
- Skills may set `model` and `context: fork` + `agent` in their frontmatter, but outside Claude Code the Agent Skills spec only allows `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`. This plugin's skills stay spec-clean on purpose, so they also load in other hosts; routing is done by the router skill and the plugin agents instead.
- `/model` lists what the account can use. There is no documented command that enumerates models programmatically.

## Codex (OpenAI) (secondary sources only; verify everything)
- Skills in the Agent Skills format (`SKILL.md`) are read from `.agents/skills/` in a project and `~/.agents/skills/` or `~/.codex/skills/` for the user; invoked with `/skills` or `$skill-name`.
- Project instructions come from `AGENTS.md`. Config is `~/.codex/config.toml` (key `model`; profiles).
- Custom subagents are reported to be TOML files in `.codex/agents/<name>.toml` with their own settings, under a multi-agent feature flag. The exact keys (including how a subagent picks its model) were not confirmed: read the current docs before writing any file, and write nothing you could not confirm.

## Antigravity (Google) (secondary sources only; verify everything)
- Skills in the same `SKILL.md` format: workspace `<root>/.agent/skills/`, global `~/.gemini/antigravity/skills/`; workspace overrides global; the agent loads a skill when its description matches the request.
- No confirmed way for a skill to set the model. Model choice is made in the product (selector per conversation/agent); the router therefore works in stages and asks the user to switch.

## Portable pattern when a host cannot delegate
1. Stage 1 (cheap model): searches, checks, conversions, written to files.
2. Stage 2 (mid model): implementation from a written brief.
3. Stage 3 (strong model, new conversation): review with the requirements, the files and the checker output; returns PASS/FIX.
Files carry the state between stages (`MODEL_ROUTING.md`, the plan, the checker output), because a new conversation has no history.
