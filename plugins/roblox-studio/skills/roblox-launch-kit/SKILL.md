---
name: "roblox-launch-kit"
description: "Prepare and run a Roblox game launch: publishing requirements (Roblox Kids/Select audiences, verification, 2FA, publishing fee or Plus/Premium, the 250 highly-engaged-plays evaluation, expedited review), Maturity & Compliance Questionnaire, store page (name, 1,000-character description with a 160-character hook, 512 px icon, 16:9 thumbnails, personalization, gameplay video rules), discovery signals (play through rate, first-play bounce, play days, playtime, co-play), Managed Pricing and dynamic prices, analytics funnels and A/B experiments, Ads Manager campaigns, events, update announcements, notifications and a 30-day live-ops calendar. Checks icon/thumbnails/title/description with a script and renders a store preview. Use whenever someone is about to publish, launch, promote, advertise or grow a Roblox game, asks why nobody plays it, wants a description, icon or thumbnail review, prices for passes/products, an ad plan or an update/event schedule, or says 'wydaję grę', 'jak wypromować grę', 'nikt nie gra', 'zrób opis gry', 'miniaturki'."
---

# Roblox Launch Kit

Goal: a launch that gets the game in front of the right players and keeps them, without hitting a publishing wall on launch day. On Roblox, distribution is earned: Recommended for You ranks games only by how organically arriving players engage (play through rate, first-session bounce, play days, playtime, co-play, spend), so the store page, the first three minutes and the reasons to return matter more than the ad budget.

Answer in the user's language; store copy in the languages the game targets (English first unless told otherwise).

Read `references/launch.md` every time: it holds the current platform rules (checked October 2026) and changes often.

## 1. Inputs
Take what is known from the conversation, `PRODUCTION_PLAN.md`, an idea-validator report or the game itself. Ask once with AskUserQuestion (multiple choice, recommended option first) only what is missing:
- State: not public yet / soft-launched / live and stagnating (then ask for the numbers: DAU, D1/D7 retention, average session, play through rate, Home Recommendation trend).
- Target audience: all ages (needs the Kids/Select evaluation) or 16+; owner: personal account or group; creator age and verification status.
- Launch date and whether it is fixed (event, creator collab, school holidays).
- Ad budget (none / small test / real campaign) and currency (card or Robux ad credits).

## 2. Readiness gate (blockers first)
Go through and mark each item done / missing / not needed:
1. **Publishing requirements** for the target audience (references section 1). For all ages: verification, 2FA, fee or 2 months of Plus/Premium, and the evaluation (trial with age-checked 16+ players until 250 unique plays by highly engaged age-checked users in 60 days). A fixed-date kids launch needs either that traffic beforehand or the 50,000 Robux expedited review: say this early, it changes the plan.
2. **Questionnaire** completed and accurate for every category.
3. **Game health**: run or offer `roblox-security-perf-audit` (exploits, backdoors, data loss, phone performance); purchases tested; Studio API access and product IDs set.
4. **First session**: playable within seconds of joining, the core loop understood in the first minute, a first reward before 60 s and a goal for the next session before 3 minutes (bounce rate is measured at < 60 s and 61-180 s). Phone controls and UI checked.
5. **Reasons to return**: daily reward or streak, next-goal UI, friends' progress, an upcoming event or update; easy co-play (invite prompts, party join, private servers).
6. **Analytics**: onboarding funnel (one step per tutorial step), shop funnel, economy events for every currency change, custom events for the core loop. Without them launch data is lost.
7. **Prices**: every Robux price in UI read from MarketplaceService (Managed Pricing changes prices per region); Dynamic Price Check done. `roblox-security-perf-audit`'s scanner flags hard-coded prices (`PRICE-HARDCODED`).

## 3. Store page
Write and check, in this order:
- **Name**: short, distinctive, says the genre or hook; no repeated words, no giveaway/Robux bait, at most one or two emojis; don't rename after launch without a reason.
- **Description**: hook in the first 160 characters (name + genre + unique feature + objective), then a short update blurb, the core loop and selling points, devices, codes, a tiny FAQ; under 1,000 characters; no hashtags or control lists.
- **Icon brief**: one subject, the game's main color, readable at 150 px and 64 px, no small text; plus 2 alternatives for later tests.
- **Thumbnail briefs** (3-5 for personalization): each sells a different reason to play (core action, social moment, progression/reward, event/update); real gameplay framed with free camera; nothing important in the bottom 15%; 1920x1080, under 3 MB.
- **Video** (optional): 15-30 s of real gameplay, rules in references section 3.

Then run the checker on the actual files (folder layout: `icon.png`, `thumbnails/*`, `title.txt`, `description.txt`):
```
python3 scripts/check_store_assets.py <store-dir> --preview store-preview.html
```
Fix every ERROR (upload rules) and every WARN unless there's a reason to keep it. Look at the preview (icon at 150/64 px on light and dark, thumbnails as Home tiles with the metadata overlay, the hook as mobile shows it); take a screenshot (Playwright or a headless browser) and actually look at it. If image-generation tools are connected, offer to mock thumbnails from real screenshots, but final images must show real gameplay.

## 4. Launch plan
Write `LAUNCH_KIT.md` in the project (ask before overwriting):

```
# <Game>: launch kit
Status, audience, launch date, budget, owner account

## Readiness gate
| Item | Status | Owner | Notes |

## Store page
Name, description (final text), icon and thumbnail briefs, checker result

## Pricing
| Item | Type (pass/product/subscription) | Price | Why this price | Dynamic price in UI |

## Measurement
Funnels and events, the 5 numbers to watch daily (PTR, first-play bounce, D1, D7, playtime per user), Home Recommendations benchmark comparison

## Traffic plan
Week 0 (private/friends test), soft launch, ad tests, community (group, Discord/YouTube/TikTok links), creators

## Ads
| Campaign | Objective | Audience | Budget/day | Days | Creatives | Success metric |

## 30-day live-ops calendar
| Week | Update / event | Goal metric | Store changes (thumbnails, event page) | Notifications |

## Risks
```

Rules for the plan:
- **Soft launch first**: limited audience or a small Plays campaign to measure PTR, bounce and D1 before spending more. Fix onboarding before scaling ads.
- **Ads**: start with Plays, small daily budget, 3-5 thumbnails per campaign, run several days before judging; Engagement objective only to reach the Kids/Select threshold (watch the Audience Reach dashboard and pause when reached). Ads help the game get considered; they don't count toward ranking, so retention decides what happens after.
- **Experiments**: one variable at a time (onboarding, starter pack, shop placement), 14+ days, one variant vs control.
- **Live-ops**: an update every 1-2 weeks with one goal metric each, events published as Experience Events (Trending Events needs 1,000+ RSVPs), update announcements to opted-in players, experience notifications for personal moments, new thumbnails tested with each major update. Plan around Saturdays and holidays.
- **Price optimization** only becomes available with roughly 60,000 transactions in 30 days; until then pick prices from comparable games and test with Experiments.

## 5. Already live and stagnating
Diagnose before prescribing: Analytics > Acquisition > Home Recommendations. Impressions fell after PTR fell -> icon/thumbnails/name; after bounce rose -> first session; after D2-7/D8-28 play days fell -> mid-term goals and content; benchmarks show which signal is furthest behind. Check the Creator Dashboard for a reduced-exposure quality banner (non-unique metadata or place, giveaway bait, mismatch). Then propose the 3 changes with the biggest expected effect and how to measure each.

## 6. Report
- Readiness verdict (ready / ready with risks / blocked by X) and the blockers with owners.
- Final store text, checker summary and preview path.
- The launch plan file and the first 3 actions for this week.
- What needs a human: verification, 2FA, paying the fee, uploading assets, the questionnaire, ad payment.

## Hand-off
`roblox-security-perf-audit` before going public; `roblox-ui-designer` for shop/onboarding UI fixes; `roblox-luau-codegen` for analytics events, dynamic prices, daily rewards, invite prompts and notifications; `roblox-game-idea-validator` if the numbers say the core loop itself doesn't hold players.
