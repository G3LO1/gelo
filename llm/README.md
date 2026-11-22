# gelo for ChatGPT, Gemini, Claude.ai and any other LLM

The skills in `plugins/roblox-studio/skills` are built for coding agents. This folder turns them into a pack that any
chat model can use, called the same way: `/gelo <task>` or `@gelo <task>`.

| File | What it is |
| --- | --- |
| [`dist/gelo-instructions.md`](dist/gelo-instructions.md) | The system prompt: who gelo is, how `/gelo` and `@gelo` work, which skill handles what, how to work without Studio tools. Under 8,000 characters, so it fits a Custom GPT. |
| [`dist/knowledge/*.md`](dist/knowledge) | One file per skill: its instructions plus all its reference files, and links to its scripts and assets. |
| [`dist/gelo-full.md`](dist/gelo-full.md) | Instructions and every knowledge file in one file (about 190 KB, roughly 50k tokens), for tools that take a single prompt or file. |

Commands, in any of them:

```
/gelo                      menu: what gelo can do, where is your game now?
/gelo idea <pitch>         is the idea worth building (GO / PIVOT / KILL)
/gelo plan                 full production plan
/gelo ui | code | anim | map
/gelo audit                security and lag audit
/gelo launch               store page, pricing, ads, live-ops
@gelo <anything>           same thing; gelo picks the skill
```

## ChatGPT (Custom GPT, then `@gelo` in any chat)

1. ChatGPT -> GPTs -> **Create** -> **Configure** (needs a plan that can create GPTs).
2. Name: `gelo`. Description: `Roblox game dev: idea, plan, code, UI, animation, maps, audit, launch.`
3. Instructions: paste the whole of `dist/gelo-instructions.md`.
4. Knowledge: upload the 8 files from `dist/knowledge/`.
5. Capabilities: turn on Web Search and Code Interpreter (it runs the Python checkers when you upload the script and your files).
6. Conversation starters: `/gelo`, `/gelo idea `, `/gelo audit`, `/gelo launch`.
7. Save. Open it directly, or in any other ChatGPT chat type `@` and pick **gelo** to pull it into that conversation
   (OpenAI's GPT mentions; on the web, the mobile apps may not offer it).

ChatGPT desktop can also read the skills themselves: install them into the project with `install.sh --for agents`
(see the root README) and call `@gelo` there.

## Gemini (Gem)

Gemini -> Gems -> **New Gem**: name `gelo`, paste `dist/gelo-instructions.md` as the instructions, add the files from
`dist/knowledge/` as knowledge, save. Open the Gem and use `/gelo ...` or just ask.

## Claude.ai (Project)

New Project `gelo`: paste `dist/gelo-instructions.md` into the project instructions and add `dist/knowledge/*.md` to
the project knowledge. Every chat in the project is gelo.

## Anything else (API, Open WebUI, LM Studio, Ollama, Le Chat, Copilot chat, ...)

- Model with a large context (64k+ tokens): use `dist/gelo-full.md` as the system prompt.
- Smaller context, or a tool with file search / RAG: `dist/gelo-instructions.md` as the system prompt and
  `dist/knowledge/*.md` as the documents.

## What works differently from Claude Code

Outside a coding agent, gelo has no Roblox Studio or Blender connection and can't run the repo's scripts by itself.
The instructions tell the model to say so and hand you the Luau for Studio's Command Bar, the Python for Blender or the
command to run locally, and to ask for the output or a screenshot back, instead of pretending it checked something.
For building straight in Studio, use Claude Code with the Roblox Studio MCP tools.

## Rebuilding

`dist/` is generated from the skills; don't edit it by hand. After changing a skill or `instructions.template.md`:

```
python3 llm/build.py
```

CI runs `python3 llm/build.py --check` and fails when `dist/` is stale or the instructions grow past 8,000 characters.
