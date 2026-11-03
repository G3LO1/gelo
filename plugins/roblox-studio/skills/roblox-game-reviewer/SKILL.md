---
name: "roblox-game-reviewer"
description: "Rate the current state of an existing or in-progress Roblox game and say what to improve: scores core loop, onboarding, progression and retention, UI/UX and mobile, polish, content runway, monetization and stability against evidence (code, playtest, scanner output, analytics), flags blockers, and returns a scorecard with a verdict (SHIP-READY / SOLID / NEEDS WORK / BROKEN) and a backlog ranked by impact per effort. A validated scoring script does the math and compares with a previous review to show progress. Use whenever someone asks to rate, review, assess, grade or critique their Roblox game as it is now, 'where are we', 'what's missing', 'what should we fix first', 'is it ready to launch', 'how good is the game', or in Polish 'oceń stan gry', 'co jest do poprawy', 'na jakim etapie jest gra', 'co poprawić najpierw', even if they don't say 'review'. For a game idea that is not built yet use roblox-game-idea-validator instead."
---

# Roblox Game Reviewer

Works on any Roblox game: run it as `/review-game [folder]` (plugin) or `/roblox-game-reviewer` (copied skills), or just ask "oceń stan gry". It reads the project's current state itself, so the user does not have to describe the game.

Goal: tell the developer how good the game is **right now** and what to fix first, with evidence. This is the middle of the workflow: `roblox-game-idea-validator` judges an idea before it is built, `roblox-security-perf-audit` hunts exploits and lag, and this skill rates the whole game as a product, then sends each weak area to the skill that fixes it.

Be direct. Inflated scores waste the developer's time; they asked because they want the real picture. Praise what is truly strong, name what holds the game back, and score only what exists today (planned work earns nothing). Answer in the user's language; criterion keys, file names and JSON stay in English.

## 1. Scope
Take what the conversation already tells you; ask only for what is missing and changes the review, with one AskUserQuestion round (multiple choice, recommended first):
- Where the game is: code on disk (Rojo project), a place open in Studio (Roblox Studio MCP), a published game (Creator Hub analytics available?), or a description only.
- Stage: prototype, vertical slice, soft launch, live. It sets expectations (a prototype is not penalized for missing live-ops, but a missing core mechanic still counts).
- Goal: learning project, side income, front page. It changes which gaps matter.
- A previous review (`review.json`) to compare against.

If the user just wants a quick take, state your assumptions in one line and review.

## 2. Gather evidence
Read `references/rubric.md`: it lists what a 1, 3 and 5 look like per criterion and where to get proof. Do the work, do not guess:
1. **Read the state**: run `python3 scripts/collect_state.py <project-folder>` (default: the current folder; Rojo project or any folder of `.luau`/`.rbxlx`). It prints script counts by side, which systems exist (saving, session lock, purchases, tutorial, audio, animation, VFX, UI, localization, analytics, pathfinding), tests/CI/linters, TODOs, placeholder IDs, debug/greybox flags, hard-coded Robux prices and the security scanner counts. These are facts, not scores. Then list the game's systems with their files and compare with the production plan (`PRODUCTION_PLAN.md` task IDs) if there is one: a data table for a mechanic is not the mechanic. For a place that is only in Studio, use Studio MCP instead (`list_roblox_studios`, `search_game_tree`, read the scripts) or ask for a `.rbxl` export and point the script at it.
2. **Run the existing tools** when they apply: `roblox-security-perf-audit` scanners (quote the counts), the project's tests (`lune run tests/...`), `roblox-launch-kit` store checker, UI/VFX validators. Say which you ran and which you could not.
3. **Playtest** if Studio MCP is connected (`start_stop_play`, `get_console_output`, screenshots; 2-3 full loops, a fresh join with empty data). Without it, say the playtest rows rest on code only.
4. **Analytics** if the game is published: day-1/day-7 retention, average session, tutorial funnel, payer conversion. Ask the user for the numbers if you cannot read them. No numbers: do not claim retention is good or bad.

Never claim the game "runs well on phones" or "is fun" without a measurement or a playtest; write what you could and could not verify.

## 3. Write review.json and score
Create `review.json` (next to the project, or `reviews/<date>.json` to keep history) with a score 1-5 and **evidence** for each of the 8 criteria, blockers, strengths and 5-12 improvements (impact 1-5, effort 1-5, aimed at one criterion). Format is in the script's docstring; a complete example is `assets/example-review.json` (a fictional game).

```
python3 scripts/review_score.py review.json [--previous reviews/last.json] [--json result.json] [--strict]
```

The script rejects missing criteria, scores outside 1-5, empty evidence, unknown criterion names and any criterion scored 1-2 that has no improvement. It computes points (weight x score / 5), the total out of 100, the verdict (80+ SHIP-READY, 65+ SOLID, 45+ NEEDS WORK, else BROKEN; **blockers cap it at NEEDS WORK**), ranks improvements by impact / effort into Do now / Next / Later, and with `--previous` shows the change per criterion. Fix the JSON until it passes; never write the totals by hand.

## 4. Report
Print the script's report, then add what it cannot:

```
# <Game>: VERDICT (score/100)
One sentence: where the game is and the single most important thing to do next.

## Scorecard            <- from the script (with Change column when there is a previous review)
## Blockers             <- from the script, fix first
## What works           <- 2-4 real strengths
## What to improve      <- from the script; Do now items first, each with the skill that does it
## How I checked        <- tools run, playtest done or not, analytics used or not, what is unverified
## Next 2 weeks         <- 3-5 concrete tasks, blockers first
```

Route each improvement to the skill that does the work: onboarding/UI/mobile -> `roblox-ui-designer`; missing systems or data -> `roblox-luau-codegen`; animation, hit feedback, effects -> `roblox-animation-vfx`; world and lighting -> `roblox-map-builder`; exploits, data loss, lag -> `roblox-security-perf-audit`; store page, pricing, live-ops -> `roblox-launch-kit`; scope or sequencing problems -> `roblox-game-production-plan`. Offer to start with the first "Do now" item.

## 5. Track progress
After the fixes (or every milestone), review again and run the script with `--previous` on the last review: the Change column shows which areas moved and whether the verdict improved. Keep the JSON files in the repo so the history is the proof of progress. If a score went down, say why (a new system exposed a gap) rather than hiding it.
