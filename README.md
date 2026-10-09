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
| [`roblox-ui-designer`](plugins/roblox-studio/skills/roblox-ui-designer/SKILL.md) | Designs and builds game UI in Figma, Photoshop or straight in Studio: proposes one of 11 researched UI styles with ready tokens, lays out mobile-safe screens, converts PSDs (`psd_to_spec.py`) and Figma designs, and turns everything into one `ui-spec.json` -> validated Studio build script + `.rbxmx` + browser preview with phone thumb-zone overlays. |
| [`roblox-security-perf-audit`](plugins/roblox-studio/skills/roblox-security-perf-audit/SKILL.md) | Audits an existing game: static Luau scanner (exploitable remotes, Toolbox backdoors, data-loss and purchase bugs, hard-coded Robux prices, lag patterns) plus a place audit that runs in Studio or on `.rbxl/.rbxm` files (physics, shadows, particles, NPCs, streaming), then a prioritized fix list. |
| [`roblox-launch-kit`](plugins/roblox-studio/skills/roblox-launch-kit/SKILL.md) | Gets a game launched and growing: publishing requirements (Kids/Select audiences, verification, fee, evaluation), questionnaire, store page copy and a checker for icon/thumbnails/title/description with a Home-tile preview, discovery signals, Managed Pricing, analytics and experiments, Ads Manager plan, events and a 30-day live-ops calendar. |
| [`roblox-animation-vfx`](plugins/roblox-studio/skills/roblox-animation-vfx/SKILL.md) | Plans and wires animations and effects from the game's mechanics: rig choice, priorities, markers, Animation Graph and IK, an animation manifest validator that generates the Luau module, an `AnimationSet` runtime, a `Vfx` preset library (hits, pickups, level ups, purchases, glows, trails) with quality and reduced-flashing settings, generated particle textures and a Studio showcase model validated against Roblox's API. |

See [`plugins/roblox-studio/README.md`](plugins/roblox-studio/README.md) for how to add new skills.

## Example

[`examples/undead-eats`](examples/undead-eats) is a co-op food-truck survival prototype made with the plugin's
workflow (validated idea, production plan, Luau code from the template, UI from a ui-spec). Its HUD and upgrade
shop are covered by a client + server integration test: `lune run tests/undead-eats/run`.

## Development

The Luau template used by `roblox-luau-codegen` has behaviour tests (session locking across two simulated servers, purchases, shutdown saves, remote validation and rate limits) that run on [Lune](https://github.com/lune-org/lune) with a mocked Roblox engine:

```
cargo install lune --locked   # or rokit/aftman
lune run tests/roblox-luau-codegen/run
```

Run them after changing anything in `plugins/roblox-studio/skills/roblox-luau-codegen/assets/template/`.

The `roblox-ui-designer` pipeline (spec -> build script -> validation against Roblox's API database via Lune's `@lune/roblox`, broken-spec cases, PSD export) has its own test:

```
pip install psd-tools pillow
bash tests/roblox-ui-designer/run.sh
```

The other skills' scripts have tests too:

```
bash tests/roblox-security-perf-audit/run.sh   # every scanner rule vs fixtures, no false positives on the template/example, place audit
bash tests/roblox-launch-kit/run.sh            # store asset checker on generated good/bad store folders
bash tests/roblox-animation-vfx/run.sh         # Vfx presets vs Roblox's API database, AnimationSet, manifest validator, textures
```

CI (`.github/workflows/ci.yml`) runs all of the above plus `claude plugin validate`, StyLua and Selene on every push to `main` and every pull request.
