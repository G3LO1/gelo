---
name: "roblox-game-idea-validator"
description: "Judge whether a Roblox game idea is good or bad before anyone builds it: scores hook, core loop, retention, social value, market saturation, mobile fit, monetization, scope and policy risk, then gives a GO / PIVOT / KILL verdict with concrete fixes and a cheap test plan. Use whenever someone pitches, compares or doubts a Roblox game concept, asks 'is this a good idea', 'will this game work/blow up/make Robux', wants feedback on a game design doc, or asks 'czy ten pomysł na grę jest dobry', 'oceń pomysł', 'czy to wypali', even if they don't say 'validate'."
---

# Roblox Game Idea Validator

Goal: tell the developer the truth about their idea before they spend weeks building it. An idea is only "good" if it can survive Roblox's discovery system, which promotes games by measured engagement (retention, playtime, spend per player), not by originality or effort. Judge the idea as a product on that platform.

Be direct. Most ideas are average; inflated scores waste the developer's time and money, and they asked because they want a real answer. Praise what is genuinely strong, name what kills the idea, and always show how it could be made better. Answer in the user's language.

## 1. Brief
Pull these from the pitch first; ask only for what is missing and actually changes the verdict, with AskUserQuestion (multiple choice, recommended option first), at most one round:
- Core loop: what the player does every 30 seconds and every session.
- Target audience (age band, casual/hardcore) and main device (assume phone-first if unknown).
- Team: size, skills (scripting, building, modeling, UI), time per week, budget for ads.
- Goal: learning project, side income, or aiming for the front page.
- Monetization plan and planned update cadence.

If the user just wants a quick take, skip questions, state your assumptions in one line, and evaluate.

## 2. Market check
Trends on Roblox turn over in months, so check the live market when web search is available: current top experiences in the genre (roblox.com/charts, RoMonitor Stats, Rolimons game list), their concurrent players, how many recent clones exist, and whether the trend is rising or fading. Name 2-4 real competitors and what they already do well. Without web access, use `references/genres.md` and say that the market data may be stale.

Read `references/genres.md` for genre-specific strengths, saturation and traps whenever the idea fits a known genre.

## 3. Score
Score each criterion 1-5 (1 = broken, 3 = average Roblox game, 5 = top-chart quality). Points = weight x score / 5 (e.g. weight 20, score 3 -> 12). Write the points for every row in the scorecard and add up that column for the total out of 100, so the reader can check the math.

| Criterion | Weight | What a 5 looks like |
| --- | --- | --- |
| Hook & clarity | 15 | Understood from the icon, thumbnail and title in 2 seconds; fun within the first 60 seconds without a tutorial wall |
| Core loop & retention | 20 | A loop players repeat for hours, short- and long-term goals, reasons to come back tomorrow (progression, timed events, collections, offline growth) |
| Social & multiplayer value | 15 | Other players make it better: co-op, competition, trading, showing off, inviting friends is natural |
| Market & differentiation | 15 | Proven demand AND a clear twist; not the 50th clone of a trend that peaked |
| Platform & audience fit | 10 | Works on a phone with simple controls and low-end devices; fits the audience's age and session length |
| Monetization fit | 10 | Players want to pay (cosmetics, convenience, passes, boosts) without it feeling pay-to-win; Premium playtime counts too |
| Scope vs team | 10 | MVP shippable by this team in about 4-8 weeks; they can keep updating it weekly |
| Content runway | 5 | Easy to add new content (items, maps, events) without rebuilding systems |

### Blockers (override the score)
Any of these caps the verdict at PIVOT (fixable) or forces KILL (not fixable):
- Breaks Roblox rules: real-money gambling, romantic/sexual themes, content above the planned maturity rating, paid random items without shown odds, harassment mechanics.
- Uses someone else's IP (anime, games, films, brands) as the selling point.
- Scope impossible for the team (MMO, open world, heavy physics/netcode for a solo beginner).
- Fun depends on many simultaneous players with no plan for empty or small servers.
- Single-player, linear, finish-once experience with no replay reason.

### Verdict
- **GO (green)**: 70+ and no blockers. Build the MVP.
- **PIVOT (yellow)**: 50-69, or a fixable blocker. Worth building only after the listed changes.
- **KILL (red)**: under 50, or an unfixable blocker. Say so plainly and offer the best salvageable part or a stronger direction.

## 4. Report
Work out the scorecard and its total BEFORE writing the verdict line: the verdict sits at the top but must quote the exact table total, and the verdict must follow the thresholds above. If a blocker changes the verdict, name that blocker in the verdict sentence (e.g. "71/100 but PIVOT: scope blocker"), otherwise readers see a score and a verdict that contradict each other.

Use this structure and keep every section, even for a KILL (the strengths are what the developer can salvage). Keep it tight:

```
# Verdict: GO / PIVOT / KILL  (score/100)
One sentence: why.

## Pitch as a player would see it
Title idea + one-line hook + what the thumbnail shows.

## Scorecard
| Criterion | Score (1-5) | Points | Why (one line) |
| ... | | | |
| **Total** | | **sum/100** | |

## What works
2-3 real strengths.

## What will kill it
2-3 biggest risks, most severe first, blockers marked.

## How to make it better
Concrete changes that raise the weakest scores (mechanics, not slogans). If PIVOT/KILL, propose 1-2 stronger versions of the idea.

## Competitors
2-4 real games: what they do, what this idea must beat.

## Cheapest test
The smallest prototype that proves the core loop (1-2 weeks), what to playtest, and the numbers that mean "keep going".
```

For the cheapest test, use rough community rules of thumb, not official Roblox numbers, and say they vary by genre: day-1 retention around 20%+ and day-7 around 5%+ is promising, average session over ~10-15 minutes is healthy, and the icon/thumbnail should earn clicks in a small paid ad test before full production.

## Comparing several ideas
Score each one with the same table, put the totals side by side, pick one winner and explain the deciding difference. Don't hedge with "they're all good".

## Hand-off
If the verdict is GO and the user wants to start building, offer to plan the MVP and to build the map with the `roblox-map-builder` skill from this plugin.
