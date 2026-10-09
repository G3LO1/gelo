# roblox-studio

Claude Code skills for making Roblox games in Roblox Studio. They work best with the Roblox Studio MCP tools connected.

## Skills

| Skill | What it does |
| --- | --- |
| [`roblox-map-builder`](skills/roblox-map-builder/SKILL.md) | Builds aesthetic, correct and performant Roblox Studio maps (terrain, buildings, lighting, props, procedural generation, validation) in any style. |
| [`roblox-game-idea-validator`](skills/roblox-game-idea-validator/SKILL.md) | Judges a Roblox game idea before you build it: scores hook, core loop, retention, social value, market, mobile fit, monetization, scope and policy risk, then gives a GO / PIVOT / KILL verdict with fixes and a cheap test plan. |

Skills are namespaced by the plugin, e.g. `/roblox-studio:roblox-map-builder`. Claude also picks them up automatically when a request matches the skill's `description`.

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
    └── roblox-map-builder/
        └── SKILL.md
```
