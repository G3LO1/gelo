# gelo

Claude Code plugin for making Roblox games in Roblox Studio.

## Install

```
/plugin install roblox-studio --marketplace G3LO1/gelo
```

On older Claude Code versions, add the marketplace first:

```
/plugin marketplace add G3LO1/gelo
/plugin install roblox-studio@gelo
```

The skills work best with the Roblox Studio MCP tools connected, so Claude can build and playtest directly in your place.

## Skills

| Skill | What it does |
| --- | --- |
| [`roblox-map-builder`](plugins/roblox-studio/skills/roblox-map-builder/SKILL.md) | Builds aesthetic, correct and performant maps (terrain, buildings, lighting, props, procedural generation, validation) in any style. |
| [`roblox-game-idea-validator`](plugins/roblox-studio/skills/roblox-game-idea-validator/SKILL.md) | Judges a Roblox game idea before you build it: scores hook, core loop, retention, social value, market, mobile fit, monetization, scope and policy risk, then gives a GO / PIVOT / KILL verdict with fixes and a cheap test plan. |

See [`plugins/roblox-studio/README.md`](plugins/roblox-studio/README.md) for how to add new skills.
