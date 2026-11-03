# Review rubric

Score each criterion 1-5: **1** broken or missing, **2** weak, **3** average Roblox game, **4** good, **5** top-chart
quality. A score without evidence is an opinion; the evidence column is mandatory and must say what you saw,
measured or read (file:line, scanner output, playtest observation, analytics number). "Looks fine" is not evidence.

Weights: core loop 20, onboarding 12, progression 16, UI/UX & mobile 12, polish 10, content 8, monetization 8,
stability 14 (total 100). A game that is not built yet is scored on what exists *now*; planned work scores nothing.

## Where to get evidence
| Source | What it gives | How |
| --- | --- | --- |
| Code on disk | Which systems exist, TODOs, hard-coded values, placeholders | Read `src/`, grep `TODO`, compare with the production plan task IDs |
| Studio MCP playtest | The real first minutes, errors, FPS feel | `start_stop_play`, `get_console_output`, screenshots; play 2-3 full loops |
| `roblox-security-perf-audit` | Exploit, data-loss and lag findings | `scan_luau.py` + place audit; quote the counts |
| Creator Hub Analytics | Retention, session length, funnels, payers | Day-1/day-7 retention, average session, tutorial funnel steps, conversion; needs a published game |
| Tests / CI | Which flows are protected | Test names, last result |
| Store page | Hook, thumbnail, title | `roblox-launch-kit` `check_store_assets.py` |

No analytics yet (unpublished game)? Say so, score those rows from playtest and code, and cap confidence: never write
"retention is good" without a number.

## Criteria

### core_loop - Core loop & fun (20)
- **1**: no loop yet (placeholders, a timer with nothing to do).
- **3**: the loop works but repeats without variation; fun comes only from numbers going up.
- **5**: a 30-second verb loop that stays fun at hour two; skill, decisions and surprise; the loop is exercised in every session.
- Check: can you describe the loop in verbs? Does every planned core mechanic exist, not just its data tables? What changes between minute 5 and minute 50?

### onboarding - First 60 seconds & onboarding (12)
- **1**: new player does not know what to do; wall of text; errors on join.
- **3**: understandable with some trial and error; tutorial exists but is skippable-or-missing for key steps.
- **5**: fun inside 60 s with no wall of text; one clear next goal at every moment; tutorial steps saved and measured as a funnel.
- Check: join as a fresh account (empty data). Time to first reward. Is there an objective on screen? Funnel drop-off if analytics exist.

### progression - Progression & retention (16)
- **1**: nothing carries between sessions.
- **3**: persistent currency or upgrades, no reason to return tomorrow.
- **5**: short, medium and long goals, daily/weekly hooks, collections, meaningful unlocks every session; data saved safely.
- Check: what does a returning player have that a new one does not? Is there a goal for day 1, day 7, day 30? Benchmarks (community rules of thumb, genre-dependent): day-1 retention 20%+ and day-7 5%+ is promising; average session 10-15+ min.

### ux_mobile - UI/UX & mobile (12)
- **1**: unusable on a phone; UI overlaps controls; text unreadable.
- **3**: works on phone and PC, some small-screen issues, no settings.
- **5**: thumb-zone layout, ScreenInsets respected, all text fits at 360x640, gamepad/keyboard paths, settings (volume, reduced flashing), localized strings, clear feedback for every action.
- Check: emulate a small phone, a tablet and 1080p. Buttons under the jump button? Hard-coded English strings? Missing prompts/ammo bars/order tickets the plan promised?

### polish - Polish: visuals, audio, game feel (10)
- **1**: grey boxes, silence.
- **3**: consistent look, some sound, few effects.
- **5**: cohesive art style, music and SFX with volume groups, animations on every verb, VFX within the phone particle budget, hit/pickup/purchase feedback.
- Check: is every important action visible, audible and animated? Greybox flags still on? Placeholder assets?

### content - Content & live-ops runway (8)
- **1**: one level, hard-coded; adding content means rewriting systems.
- **3**: data-driven tables but little content.
- **5**: content added by editing data (items, maps, events); a calendar for the next 4-8 weeks.
- Check: `Recipes`/`Items`/`Waves` style tables vs hard-coded `if` chains; how many hours of distinct content exist?

### monetization - Monetization health (8)
- **1**: pay-to-win, paid randomness without odds, or purchases broken.
- **3**: sensible offers, but placeholders or hard-coded prices.
- **5**: cosmetics/convenience/passes with a free path to every feature, idempotent receipts, prices from MarketplaceService, offers surfaced at natural moments, nothing that violates policy.
- Check: product IDs still `0`/TODO? Any feature gated only by Robux? Is the shop reachable but never nagging? An unpublished game with no monetization wired scores 1-2 here, not "n/a".

### stability - Stability, security & performance (14)
- **1**: exploitable currency/data loss/crashes.
- **3**: no known exploits, untested on low-end phones.
- **5**: clean scanner + place audit, remotes validated and rate limited, session-locked saves, tested flows, measured FPS and memory on a real low-end phone.
- Check: run `roblox-security-perf-audit`; list tests and what they cover; never claim phone performance without a measurement.

## Blockers
A blocker caps the verdict at NEEDS WORK however high the score. Put it in `blockers` with evidence:
- A client can grant itself currency, items or other players' state; backdoor in a model.
- Data loss or duplication (no session lock, `SetAsync` over a profile, receipts not idempotent).
- Crash, softlock or hard error on join/in the core loop; unplayable on phones.
- Policy violation (paid random items without odds, content above the maturity rating, someone else's IP as the hook).
- The core loop's central mechanic does not exist yet (the game cannot be completed or fun-tested).

## Improvements
List 5-12, each aimed at one criterion with `impact` 1-5 (how much it raises the game's score or retention) and
`effort` 1-5 (1 = under half a day, 3 = a few days, 5 = weeks). The script ranks them by impact / effort. Rules:
- Fix blockers first, regardless of rank.
- Concrete changes, not slogans: "add a 5-step tutorial saved to `TutorialStep` and logged as a funnel", not "improve onboarding".
- Every criterion scored 1 or 2 needs at least one improvement.
- Do not pad with nice-to-haves; cut anything that would not move a score or a metric.
