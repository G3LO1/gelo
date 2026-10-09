# roblox-studio

Claude Code skills for making Roblox games in Roblox Studio. They work best with the Roblox Studio MCP tools connected.

## Skills

| Skill | What it does |
| --- | --- |
| [`roblox-map-builder`](skills/roblox-map-builder/SKILL.md) | Builds aesthetic, correct and performant Roblox Studio maps (terrain, buildings, lighting, props, procedural generation, validation) in any style. |
| [`roblox-game-idea-validator`](skills/roblox-game-idea-validator/SKILL.md) | Judges a Roblox game idea before you build it: scores hook, core loop, retention, social value, market, mobile fit, monetization, scope and policy risk, then gives a GO / PIVOT / KILL verdict with fixes and a cheap test plan. |
| [`roblox-game-production-plan`](skills/roblox-game-production-plan/SKILL.md) | Turns a (validated) idea into a full production plan: every system, 3D model, animation, UI screen, sound, VFX, monetization, analytics and publishing task, with owners, sizes, priorities, a capacity check and milestones. Uses current Roblox specs (mesh/texture limits, asset permissions, DataStore limits, Creator Rewards, maturity questionnaire). |
| [`roblox-luau-codegen`](skills/roblox-luau-codegen/SKILL.md) | Writes the game's Luau code from the plan (Rojo project or straight into Studio): a tested template with session-locked player data, idempotent purchases and validated, rate-limited remotes, plus the game's own systems built from ready patterns, checked with StyLua/Selene. |
| [`roblox-ui-designer`](skills/roblox-ui-designer/SKILL.md) | Designs and builds game UI in Figma, Photoshop or straight in Studio: proposes one of 11 researched UI styles with ready tokens, lays out mobile-safe screens, converts PSDs (`psd_to_spec.py`) and Figma designs, and turns everything into one `ui-spec.json` -> validated Studio build script + `.rbxmx` + browser preview with phone thumb-zone overlays. |
| [`roblox-security-perf-audit`](skills/roblox-security-perf-audit/SKILL.md) | Audits an existing game: static Luau scanner (exploitable remotes, Toolbox backdoors, data-loss and purchase bugs, hard-coded Robux prices, lag patterns) plus a place audit that runs in Studio or on `.rbxl/.rbxm` files (physics, shadows, particles, NPCs, streaming), then a prioritized fix list. |
| [`roblox-launch-kit`](skills/roblox-launch-kit/SKILL.md) | Gets a game launched and growing: publishing requirements (Kids/Select audiences, verification, fee, evaluation), questionnaire, store page copy and a checker for icon/thumbnails/title/description with a Home-tile preview, discovery signals, Managed Pricing, analytics and experiments, Ads Manager plan, events and a 30-day live-ops calendar. |
| [`roblox-animation-vfx`](skills/roblox-animation-vfx/SKILL.md) | Plans and wires animations and effects from the game's mechanics: rig choice, priorities, markers, Animation Graph and IK, an animation manifest validator that generates the Luau module, an `AnimationSet` runtime, a `Vfx` preset library (hits, pickups, level ups, purchases, glows, trails) with quality and reduced-flashing settings, generated particle textures and a Studio showcase model validated against Roblox's API. |

Skills are namespaced by the plugin, e.g. `/roblox-studio:roblox-map-builder`. Claude also picks them up automatically when a request matches the skill's `description`.

## Workflow

1. `roblox-game-idea-validator`: is the idea worth building? (GO / PIVOT / KILL)
2. `roblox-game-production-plan`: everything that has to be made, by whom, and when.
3. `roblox-ui-designer`: pick a UI style and build the screens (Figma, Photoshop or Studio).
4. `roblox-luau-codegen`: write the code for the plan's systems and UI controllers.
5. `roblox-animation-vfx`: animation list and manifest, effects for every moment, wired into that code.
6. `roblox-map-builder`: build the world in Studio.
7. `roblox-security-perf-audit`: before launch (and whenever exploiters or lag show up), audit code and place and fix what matters.
8. `roblox-launch-kit`: publishing requirements, store page, pricing, ads and the first month of live-ops.

## Install

```
/plugin install roblox-studio --marketplace G3LO1/gelo
```

## Adding a new skill

1. Create `skills/<skill-name>/SKILL.md` (lowercase, hyphens, the folder name is the skill name).
2. Start it with frontmatter:

   ```markdown
   ---
   name: "<skill-name>"
   description: "What the skill does and WHEN to use it: concrete triggers, keywords, languages."
   ---

   # Skill title

   Instructions for Claude...
   ```

   The `description` decides when Claude loads the skill, so put the trigger phrases there.
3. Optional extras go next to `SKILL.md` (`references/*.md`, `scripts/*`, `assets/*`); link them from `SKILL.md` so Claude reads them only when needed.
4. Add a row to the table above, bump `version` in `.claude-plugin/plugin.json` and in the root `.claude-plugin/marketplace.json` (keep them equal).
5. Validate before pushing:

   ```
   claude plugin validate plugins/roblox-studio
   claude plugin validate .
   ```

6. Users pick up the new version with `/plugin update roblox-studio`.

## Layout

```
plugins/roblox-studio/
├── .claude-plugin/plugin.json   # plugin manifest
├── README.md
└── skills/
    ├── roblox-game-idea-validator/
    │   ├── SKILL.md
    │   └── references/genres.md
    ├── roblox-game-production-plan/
    │   ├── SKILL.md
    │   └── references/production-checklist.md
    ├── roblox-luau-codegen/
    │   ├── SKILL.md
    │   ├── references/patterns.md
    │   ├── scripts/check.sh
    │   └── assets/template/        # Rojo project: Data/Purchase services, Net, Guard, Config
    ├── roblox-ui-designer/
    │   ├── SKILL.md
    │   ├── references/             # ui-styles, studio, figma, photoshop, ui-spec
    │   ├── scripts/                # spec_to_luau.py, validate_ui.luau, psd_to_spec.py, preview_ui.py
    │   └── assets/                 # ui_builder.luau, examples/style-tile-bubbly.json
    ├── roblox-map-builder/
    │   └── SKILL.md
    ├── roblox-security-perf-audit/
    │   ├── SKILL.md
    │   ├── references/             # security, performance
    │   └── scripts/                # scan_luau.py, audit_studio.luau, audit_place.luau
    ├── roblox-launch-kit/
    │   ├── SKILL.md
    │   ├── references/launch.md    # publishing, store page, discovery, pricing, ads, live-ops
    │   └── scripts/check_store_assets.py
    └── roblox-animation-vfx/
        ├── SKILL.md
        ├── references/             # animation, vfx
        ├── scripts/                # anim_manifest.py, vfx_showcase.luau, make_textures.py
        └── assets/                 # Vfx.luau, AnimationSet.luau, textures/
```
