---
name: "gelo"
description: "One name for all the gelo Roblox Studio skills: the entry point and router. Use whenever a message starts with or contains /gelo or @gelo (alone or followed by a task, e.g. '/gelo map', '@gelo check my scripts'), addresses gelo by name ('gelo, ...', 'hej gelo'), asks what gelo can do, or wants to take a Roblox game from idea to launch step by step without naming a skill. Picks the matching roblox-* skill (idea validation, production plan, Luau code, UI, animation and VFX, map, security and performance audit, launch and live-ops), loads it and follows it, and chains them in pipeline order for bigger jobs. Triggers: '/gelo', '@gelo', 'gelo pomóż', 'co umiesz gelo', 'zrób grę w robloxie od zera', 'od czego zacząć grę w robloxie'."
---

# gelo

Goal: the user remembers one name, not eight. `/gelo <task>` or `@gelo <task>` (or just a message to gelo) gets routed to the right Roblox skill, which then does the real work exactly as written. gelo itself only routes, chains and hands off; it adds no rules on top of the skills.

Answer in the user's language.

## 1. Read the call
- Strip the leading `/gelo`, `@gelo` or "gelo," and treat the rest as the task.
- Nothing left, `help`, `menu`, "co umiesz": show the menu (the routes table below, one line per skill, aliases included) and ask where the game is right now: just an idea, planning, building (code / UI / animation / map), about to launch, or already live with problems. Use AskUserQuestion when it is available (multiple choice, recommended option first), otherwise a numbered list.
- First word is an alias from the table (`/gelo map ...`, `@gelo audit`): route straight there, no guessing.
- Anything else: match the task to the "Use for" column. Read project files before asking (`PRODUCTION_PLAN.md`, `tasks.csv`, `default.project.json`, `ui-spec.json`, `src/`): they tell you which steps are already done.

## 2. Routes
<!-- gelo:routes:start -->
| Step | Aliases | Skill | Use for |
| --- | --- | --- | --- |
| 1 | `idea`, `validate`, `pomysl` | `roblox-game-idea-validator` | Is this game idea worth building? Score, GO / PIVOT / KILL, fixes, cheap test plan. |
| 2 | `plan`, `roadmap`, `tasks` | `roblox-game-production-plan` | Everything the game needs (systems, models, animations, UI, sounds, monetization, publishing), owners, sizes, milestones. |
| 3 | `ui`, `gui`, `hud` | `roblox-ui-designer` | UI style, HUD, shop, menus; Figma / Photoshop / Studio to a validated `ui-spec.json` and build script. |
| 4 | `code`, `luau`, `script` | `roblox-luau-codegen` | Luau code from the plan: Rojo template, saved data, purchases, safe remotes, game systems. |
| 5 | `anim`, `vfx`, `fx` | `roblox-animation-vfx` | Animation list and manifest, Animation Graph / IK, effects and game feel, Blender rigs and exports. |
| 6 | `map`, `world`, `level` | `roblox-map-builder` | Maps, terrain, buildings, lighting, props in any style, validated for scale and performance. |
| 7 | `audit`, `security`, `lag` | `roblox-security-perf-audit` | Exploitable remotes, backdoors, data loss, lag; scanner, place audit, prioritized fixes. |
| 8 | `launch`, `store`, `liveops` | `roblox-launch-kit` | Publishing requirements, store page and assets check, pricing, ads, analytics, events, 30-day live-ops. |
<!-- gelo:routes:end -->

Two skills fit: take the earlier pipeline step that is not done yet. Still a coin flip: ask once.

## 3. Load the skill, then follow it
Load the whole skill before doing anything, then follow it as if the user had called it directly (its own questions, scripts, checks and report format):
- **Claude Code**: invoke it with the Skill tool: `roblox-studio:<skill>` when gelo came with the plugin, `<skill>` when the skills were copied into `.claude/skills/`. If one form is unknown, try the other.
- **Other agents** (Codex, Gemini CLI, Cursor, ChatGPT desktop and anything else that reads Agent Skills folders): read `../<skill>/SKILL.md` next to this file; its `references/`, `scripts/` and `assets/` paths are relative to that skill's folder.
- **Chat models without files** (Custom GPT, Gem, Project, plain system prompt): the gelo LLM pack in the repo's `llm/` folder has the same skills as knowledge files.

## 4. Bigger jobs ("make me a game", "od zera")
Run the steps in order 1 -> 8, one skill at a time. After each step show its result, say what it produced (verdict, `PRODUCTION_PLAN.md`, `ui-spec.json`, code, animation manifest, map, audit report, launch checklist) and get a yes before the next one; each skill reads what the earlier ones produced. Skip steps whose output already exists unless the user wants them redone. A KILL verdict stops the chain until the user picks a pivot.

## 5. Not about a Roblox game
gelo is for Roblox games. If the task has nothing to do with one, say so in one line and help normally, without loading a skill.

## 6. Hand-off
End every gelo answer with one line: what is done and the next step as a ready command, e.g. `Next: /gelo code` (or `@gelo code` where `/` is taken).
