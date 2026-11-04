---
name: "roblox-start"
description: "Entry point for Roblox game work: finds out what the user wants to do and routes to the right skill with clickable questions instead of free text. Use when someone starts a Roblox game project or asks for help with their game without a specific task: 'chcę zrobić grę', 'chcę naprawić grę', 'co teraz', 'od czego zacząć', 'pomóż z moją grą w Roblox', 'I want to make a Roblox game', 'fix my Roblox game', 'where do I start', 'what should I do next'. Picks between making a new game, fixing or improving an existing one, launching and growing a live one, or one specific job (UI, map, animation, code), then hands over to the matching roblox-* skill."
---

# Roblox Start

Goal: the user never has to know the skill names or type a menu choice. Look at what is already in the project, ask the few questions that decide the path, and hand over to the right skill with the answers, so it doesn't ask them again.

Answer in the user's language; skill names, files and code stay in English.

## How to ask
Every choice and every confirmation goes through AskUserQuestion, never as a numbered list or a question in plain text. Rules (details and templates: `references/asking.md`):
- One round at a time, 1-4 related questions per call, 2-4 options each. The recommended option goes first and ends with "(Recommended)". "Other" is added automatically, don't add it.
- Option labels are short (1-5 words); the description says what happens if it is picked.
- Never ask what the conversation or the project already answers. If the request is already specific ("scan my remotes for exploits"), skip this skill and use the matching one.
- If the user answers "Other" with text, treat it as the answer and continue.

## 1. Look first (no questions yet)
Check quickly, without reading whole files:
- `PRODUCTION_PLAN.md`, `tasks.csv`, `LAUNCH_KIT.md`, `animations.json`, `ui/ui-spec.json` in the project.
- `default.project.json` / `src/` (a Rojo project), `*.rbxl`, `*.rbxlx`, `*.rbxm`.
- Connected tools: Roblox Studio MCP (`list_roblox_studios`), Blender MCP (tools with `blender` in the name), Figma MCP.

Use it to pick the recommended option below and to say, in one line, what you found ("Found a plan and a Rojo project, no UI yet").

## 2. Question 1: the path
AskUserQuestion, header "Path". Recommended = the option the findings point to (nothing found -> new game; code and place found -> fix).
| Option | Meaning |
| --- | --- |
| Make a new game | There is an idea or nothing yet; go from idea to a built game |
| Fix or improve my game | An existing game has bugs, exploits, lag, or something missing |
| Launch and grow it | The game is built or live; publishing, store page, ads, live-ops |
| One specific job | UI, map, animations and effects, or code for one system |

## 3. Question 2: depends on the path
Ask only the branch that matches. Each option names the skill it leads to.

**Make a new game**: "Where are you with it?"
- Only a rough idea -> `roblox-game-idea-validator`.
- Validated idea, no plan -> `roblox-game-production-plan`.
- Plan exists -> next unfinished step: UI (`roblox-ui-designer`), code (`roblox-luau-codegen`), animation and effects (`roblox-animation-vfx`), map (`roblox-map-builder`); recommend the first one with nothing built yet.
- No idea at all -> `roblox-game-idea-validator` in comparison mode: propose 3 concepts as options, let the user pick, then score them.

**Fix or improve**: "What is wrong?" (multiSelect allowed when it is several things)
- Exploiters, hacked or duplicated currency, data loss, a suspicious free model -> `roblox-security-perf-audit` (security and data).
- Lag, low FPS, crashes on phones -> `roblox-security-perf-audit` (performance).
- A system is broken or missing -> `roblox-luau-codegen`.
- Looks wrong or feels flat -> UI `roblox-ui-designer`, world `roblox-map-builder`, motion and effects `roblox-animation-vfx`: ask which with a third question.
- Players join but don't stay, or don't come -> `roblox-launch-kit` section 5 (diagnose before prescribing); if the core loop itself is the problem, `roblox-game-idea-validator`.

**Launch and grow**: "What do you need?" -> readiness gate and store page (`roblox-launch-kit`), an audit before going public (`roblox-security-perf-audit`), ads and live-ops (`roblox-launch-kit`).

**One specific job**: "Which one?" -> UI, map, animations and effects, code.

## 4. Question 3: only what the target skill would ask first
Ask at most one more round, and only the inputs the target skill needs and the project doesn't hold (for example: Rojo on disk / straight into Studio / paste-ready for code; Studio, Figma or Photoshop for UI; what to audit and whether Claude may patch). Put these questions in the same AskUserQuestion call as question 2 when they don't depend on its answer.

## 5. Hand over
Say in one line which skill you are starting and why, then invoke it with the Skill tool, passing the answers as context ("path: fix; symptom: lag on phones; may patch: no"). The target skill must not re-ask anything already answered.

When that skill finishes, close with one AskUserQuestion: "What next?" with the natural follow-ups as options (the hand-off targets of the skill that just ran, recommended first) and "Nothing, we're done".

## Hand-off
Every other skill in this plugin; this one only routes and never builds anything itself.
