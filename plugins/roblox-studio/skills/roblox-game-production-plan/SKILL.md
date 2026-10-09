---
name: "roblox-game-production-plan"
description: "Turn a Roblox game idea into a full production plan: every script/system, 3D model, character animation, UI screen, sound, VFX, map, monetization item, analytics event and publishing/compliance step the game needs, with owners, size estimates, priorities (MVP / launch / post-launch), dependencies and milestones that fit the team's capacity. Use after an idea is validated, or whenever someone asks what they need to make/build/ship their Roblox game, wants a roadmap, task list, backlog, GDD, scope or timeline, or asks 'co trzeba zrobić', 'rozpisz plan gry', 'jakie animacje/modele/UI potrzebuję'."
---

# Roblox Game Production Plan

Goal: a plan the team can start working from tomorrow, where nothing the game needs to function and ship is forgotten (animation permissions, save data, receipts, the maturity questionnaire and the icon are the usual surprises), and where the scope honestly fits the people and weeks available.

Answer in the user's language. Plans are only useful if they are specific to this game: "Animations" is not a task, "Chef chop loop (R15, Action priority, 1.2 s)" is.

## 1. Inputs
Start from what is already known in the conversation, especially a `roblox-game-idea-validator` report (use its fixes, not the original weaker pitch). If the idea was never validated and looks risky, say so in one line and offer to validate it first, but don't block.

Ask only for what is missing, with AskUserQuestion (multiple choice, recommended option first), one round:
- Team: people, roles (scripter, builder, 3D modeler, animator, UI, sound), hours per week, any money for assets, ads or freelancers.
- Deadline or target: playable prototype date, public launch date.
- Art direction: style (low-poly, cartoon, realistic...), avatar type (players' own R15 avatars, custom StarterCharacter, or R6).
- Platforms: phone-first is the default; console/VR only if asked.
- Owner account: personal or group (it decides who must upload animations and audio).
- Tools: Blender (and whether a Blender MCP server is or can be connected, so Claude can help with models, rigs, animation blocking and exports), Figma/Photoshop for UI, Roblox Studio MCP. If a Blender MCP server is already connected (tools with `blender` in the name), note it instead of asking. AI-assisted Blender work shortens technical and blocking tasks, not animation polish: size tasks accordingly. Setup and limits: `../roblox-animation-vfx/references/blender.md`.

If the user wants it fast, assume sensible defaults, list the assumptions at the top, and continue.

## 2. Break the game down
1. **Core loop and systems.** Write the loop as verbs (e.g. collect -> cook -> sell -> upgrade -> defend). List every gameplay system behind it plus the invisible ones every game needs: player data saving, purchases, settings, onboarding, anti-exploit checks on remotes.
2. **Mechanic -> asset matrix.** For every player-facing verb or event, fill one row: server logic, client feedback, animation, model, VFX, SFX, UI. This is how nothing gets forgotten: a "throw" mechanic needs a throw animation, a projectile model, a trail, a whoosh and an impact sound, a cooldown indicator and a server hit check. Show this matrix in the plan.
3. **Expand per discipline** using `references/production-checklist.md` (read it every time, it holds the current Roblox specs and the steps teams forget). Disciplines: systems/scripting, data, 3D models, characters and animation, UI, audio, VFX, world/map, monetization, analytics, publishing and compliance, QA and performance, launch and live-ops.
4. **Size and prioritize each task.** Size S (under 1 day), M (1-3 days), L (3-7 days), XL (over a week: split it). Priority: MVP (needed to test the core loop with real players), Launch (needed for a public release that can earn and retain), Post-launch (first updates). Note the owner role and dependencies.
5. **Fit the scope to capacity.** Add up the days per role and compare with the hours the team actually has, keeping about 30% buffer for bugs and polish. If it doesn't fit, cut or simplify (Toolbox/Creator Store assets, fewer variants, reuse animations) and say clearly what was cut. Don't quietly give an impossible plan.

## 3. Milestones
Use these unless the user has their own:
1. **Prototype / greybox** (1-2 weeks): core loop playable with plain parts and placeholder UI, no art. Exit: people play 10+ minutes without being asked.
2. **Vertical slice**: one area, final-quality art, animation, sound and UI for the core loop. Exit: it looks and feels like the real game.
3. **MVP / soft launch**: saving, monetization, analytics, onboarding, mobile UI, questionnaire done; public with a small audience (friends, small ad test). Exit: day-1 / day-7 retention and session length are measurable and improving.
4. **Launch**: content for the first weeks, icon/thumbnails/video, social links, first event ready.
5. **Live-ops**: update cadence (weekly or bi-weekly), event calendar, what gets measured each update.

## 4. Output
Write the plan as a Markdown file in the user's project (default `PRODUCTION_PLAN.md`, ask before overwriting an existing one) and summarize it in chat. When the user wants to import tasks into a board (Trello, Notion, GitHub Projects, Jira), also write `tasks.csv` with columns `id,discipline,task,owner,size,priority,milestone,depends_on`.

Plan structure:

```
# <Game name>: production plan
Assumptions (team, deadline, style, platforms, owner account)

## Core loop & systems
## Mechanic -> asset matrix
| Mechanic | Server | Client feedback | Animation | Model | VFX | SFX | UI |

## Tasks by discipline
### Systems & scripting / Data / 3D models / Characters & animation / UI / Audio / VFX / World & map / Monetization / Analytics / Publishing & compliance / QA & performance / Launch & live-ops
| ID | Task | Owner | Size | Priority | Depends on |

## Capacity check
Days per role vs available days, buffer, what was cut or simplified.

## Milestones & timeline
Week-by-week or milestone list with exit criteria.

## Risks
Top 3-5 production risks and the mitigation for each.

## First week
The exact tasks each person starts with on day 1.
```

## Hand-off
For the world/map tasks offer the `roblox-map-builder` skill from this plugin; for animation and VFX tasks `roblox-animation-vfx` (which also drives Blender through a Blender MCP server when one is connected). When Roblox Studio MCP tools are connected and the user wants to start, offer to set up the place structure (folders, RemoteEvents, a data module, placeholder UI) from the plan.
