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
| [`roblox-game-production-plan`](plugins/roblox-studio/skills/roblox-game-production-plan/SKILL.md) | Turns a (validated) idea into a full production plan: every system, 3D model, animation, UI screen, sound, VFX, monetization, analytics and publishing task, with owners, sizes, priorities, a capacity check and milestones. Uses current Roblox specs (mesh/texture limits, asset permissions, DataStore limits, Creator Rewards, maturity questionnaire). |
| [`roblox-luau-codegen`](plugins/roblox-studio/skills/roblox-luau-codegen/SKILL.md) | Writes the game's Luau code from the plan (Rojo project or straight into Studio): a tested template with session-locked player data, idempotent purchases and validated, rate-limited remotes, plus the game's own systems built from ready patterns, checked with StyLua/Selene. |

See [`plugins/roblox-studio/README.md`](plugins/roblox-studio/README.md) for how to add new skills.

## Development

The Luau template used by `roblox-luau-codegen` has behaviour tests (session locking across two simulated servers, purchases, shutdown saves, remote validation and rate limits) that run on [Lune](https://github.com/lune-org/lune) with a mocked Roblox engine:

```
cargo install lune --locked   # or rokit/aftman
lune run tests/roblox-luau-codegen/run
```

Run them after changing anything in `plugins/roblox-studio/skills/roblox-luau-codegen/assets/template/`.
