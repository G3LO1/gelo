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

### Or copy the skills into your game's folder

One command puts all skills in the project's `.claude/skills/`, so they work for anyone who opens that folder in
Claude Code (commit them with the game) and show up as `/roblox-map-builder` etc. Run it from the game's folder:

```
# macOS / Linux / Git Bash
curl -fsSL https://raw.githubusercontent.com/G3LO1/gelo/main/install.sh | bash

# Windows PowerShell
irm https://raw.githubusercontent.com/G3LO1/gelo/main/install.ps1 | iex
```

From a clone: `bash install.sh [game-folder]` or `powershell -ExecutionPolicy Bypass -File install.ps1 [-Project "D:\Game"]`.
For every project at once use `--global` / `-Global` (-> `~/.claude/skills/`); piped in, that's
`| bash -s -- --global` or `& ([scriptblock]::Create((irm https://raw.githubusercontent.com/G3LO1/gelo/main/install.ps1))) -Global`.
Running it again updates the skills and leaves your other skills alone. Use the plugin or the copied skills, not both,
or every skill shows up twice.

The skills work best with the Roblox Studio MCP tools connected, so Claude can build and playtest directly in your place. If you use Blender, connect a Blender MCP server too (e.g. [MCP for Blender](https://github.com/ahujasid/blender-mcp)); the skills ask about it when a task needs 3D models or animation and use it when it's there.

## Skills

Ten skills covering the whole path from idea to live-ops: idea validation, production plan, monetization and economy,
Luau code, UI, animation and VFX, maps, security and performance audit, launch kit. The full list with descriptions and the recommended workflow
is in [`plugins/roblox-studio/README.md`](plugins/roblox-studio/README.md).

Adding a new skill: see the same README.

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
bash tests/roblox-model-router/run.sh         # model detection on fake Claude Code/Codex/Antigravity setups, agent frontmatter
bash tests/roblox-monetization-designer/run.sh # economy/price checker on good/bad specs, generated Products module
bash tests/roblox-animation-vfx/run.sh         # Vfx presets vs Roblox's API database, AnimationSet, manifest validator, textures
                                               # + blender_check.py on real Blender when bpy is installed (BPY_PYTHON=...)
bash tests/install/run.sh                      # install.sh / install.ps1 (pwsh): folder, --global, piped-in download
```

CI (`.github/workflows/ci.yml`) runs all of the above plus `claude plugin validate`, StyLua and Selene on every push to `main` and every pull request.
