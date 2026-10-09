# Launch reference

Platform facts for publishing, discovery, pricing, ads and live-ops. Checked against create.roblox.com (Roblox/creator-docs) on 9 October 2026; Roblox changes these often, so re-check anything a launch date depends on. Items marked (verify) were not confirmed in that check.

## Contents
1. Who can play: audiences and publishing requirements
2. Maturity & Compliance Questionnaire
3. Store page: name, description, icon, thumbnails, video
4. How discovery works
5. Monetization and Managed Pricing
6. Analytics and experiments
7. Ads Manager
8. Events, update announcements, notifications
9. Earning programs

## 1. Who can play
Accounts are split by age (self-declared until age-checked):

| Account | Ages | Content it can see | Chat |
| --- | --- | --- | --- |
| Roblox Kids | 5-8 | Minimal, Mild | off by default; parent can enable after age check |
| Roblox Select | 9-15 (or self-declared 9+ until checked) | Minimal, Mild, Moderate | off for self-declared; gradual with safeguards once checked |
| Roblox | age-checked 16+ | all rated content except Restricted (18+) | on by default where available |

**Reach 16+ (and Trusted Friends):** account in good standing and at least 2 days old, age verification (facial age estimation or government ID), Maturity & Compliance Questionnaire completed.

**Reach all ages (Kids and Select too):** all of the above plus
- account verification: facial age estimation if under 18, government ID if 18+; group games: the group owner;
- 2-step verification on the account;
- one of: an active Roblox Plus or Premium subscription for 2 consecutive months, OR the refundable publishing fee of 1,000 Robux per game (refunded when the game keeps 25 highly engaged players for 60 days without moderation; not refunded if the game is permanently moderated);
- evaluation: the game first runs as a trial for age-checked 16+ users; Roblox checks engagement is real (account age, play history, platform spend) and reviews safety; the game becomes eligible after **250 unique plays by highly engaged age-checked users within 60 days**. Progress: Creator Hub > Audience Reach dashboard.
- A "highly engaged player" currently needs account tenure, playtime in your game, and a purchase anywhere on Roblox in the last 60 days (not necessarily in your game).
- **Expedited review**: one-time refundable 50,000 Robux per game for timed launches or off-platform campaigns; refundable after 90 days if the game is in good standing with 25 highly engaged players.

Other publishing facts: up to 5 never-public private games can be made public per day; "Private" now means only editors can play; to let testers in, set Audience to Limited > Playtesters (requires meeting the public requirements). Public games can opt out of Recommended For You ("Exclude from Recommendations").

Launch implication: a brand-new game starts with 16+ age-checked players only. Plan the first weeks (ads, community, friends) to reach the 250 highly engaged plays, or budget the expedited fee for a fixed-date launch aimed at kids.

## 2. Maturity & Compliance Questionnaire
Answer accurately and update it when content changes. Categories: violence, blood, fear, crude humor, unplayable gambling content, strong language, romantic themes, alcohol, social hangout, free-form user creation, sensitive issues, paid random items, paid item trading, media, AI interaction. Labels: Minimal, Mild, Moderate, Restricted (18+ ID-verified only; the creator must be 18+ and verified). Unrated games lose reach. Source: production/promotion/content-maturity.

## 3. Store page
**Name**: keep it stable (renames lose search), no repeated words ("Obby Madness OBBY OBBY" gets demoted), at most one or two well-placed emojis. No official length limit is documented; short names read best on tiles.

**Description** (experimental guidelines, production/publishing/descriptions):
- 1,000-character budget.
- Hook = first ~160 characters: title, core genre, the most unique feature, primary search terms, the main objective. It is what search snippets and the collapsed mobile description show.
- Optional short "recent update" blurb; main content = core loop and selling points (bullets or a paragraph); additional info = devices, codes, short FAQ, link to a DevForum changelog.
- No tags/hashtags (unused by ranking), no control lists (teach them in game), all-ages wording.

**Icon** (production/publishing/experience-icons): square, 512x512 (at least); it is shown down to 150x150 and smaller, so preview it small. One icon per locale; must pass moderation. Express theme/tone/genre; unique and relevant imagery, strong color and contrast.

**Thumbnails** (production/publishing/thumbnails):
- Up to 10 images/videos on the detail page; images 16:9, ideally 1920x1080 (other ratios get stretched to 16:9); .jpg .gif .png .tga .bmp; Home page uploads under 3 MB.
- Don't put essential text or elements at the bottom: metadata like the player count can cover it.
- Thumbnail personalization (Home page tab): activate 2-5 thumbnails; Roblox shows each to random users, then gives more impressions to the winner per user group while still exploring. Measured by **qualified play through rate** (qualified plays / Home impressions). Reported average +8.5% qualified PTR, up to +50%. Keep several active; test new ones with each major update, then leave them until the next.
- Video: authentic gameplay only; free camera (Left Shift + P in a solo playtest), light color grading, logo overlay, Roblox catalog music are fine; no voice-over, narration or music with lyrics, no real-world footage, no ads/claims ("50% off", "Free UGC!"), no mechanics or graphics the game doesn't have. 3 video uploads per month (rejections count). Not shown on Xbox, PlayStation, VR.

**Other**: genre, supported devices, social links (production/promotion/social-media-links), localized name/description/icon for big languages (production/localization), badges for milestones (production/publishing/badges).

## 4. How discovery works (discovery.md)
Recommended for You works in two stages: **retrieval** (which games are considered for a user; helped by ads, curation, search, charts, friends, notifications, social sharing, even a small number of players) and **ranking** (how far it goes: ONLY the engagement of users who arrived organically from Recommended for You counts; ad, search, friend and social traffic do not count here).

Signals, averaged per user (small games are not disadvantaged):
- Most important: play through rate (plays after seeing it in Recommended for You); first play bounce rate (negative; < 60 s and 61-180 s sessions); play days per user and playtime per user (D1, D2-7, D8-28; playtime capped at 60 min per user per day).
- Important: intentional co-play days (friends joining, invites, private servers), qualified play sessions per user, spend days per user, Robux spent per user.
- Explore and expand: after an update Roblox may test the game on new cohorts; if they engage, it widens distribution.
- Weekly seasonality (peaks Saturday), summer/school, holidays.

What limits exposure: metadata leading with giveaways or Robux ("Robux! Play now!"), metadata that doesn't match gameplay, non-unique games (titles, images or place files close to existing games, also makes ads spend nothing). A banner on the Creator Dashboard shows quality issues; content quality is reassessed with every update.

Launch implications: the first 60-180 seconds decide the bounce signal (instant action, no long loading or menus); give a reason to come back tomorrow and in week 2-4 (play days); make playing with friends easy (co-play days); monitor Analytics > Acquisition > Home Recommendations against the benchmark games.

Other surfaces: Search (semantic, natural-language queries in supported languages), Discover charts and Trending, Standout Games (hand-curated), Live Events, Sponsored, game details page (events, groups, passes, similar games), notifications.

## 5. Monetization and Managed Pricing
- **Managed Pricing** (Monetization > Managed Pricing) = regional pricing + price optimization under one opt-in. New games and newly created items are enrolled by default; passes have regional pricing on by default; subscriptions, private servers and developer servers are regionalized automatically.
- Regional prices stay between 30% and 100% of your default price; economic location uses signals like VPN usage, billing and account history.
- Developer products need **dynamically scripted prices** before enabling: read `MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)` (passes: `Enum.InfoType.GamePasses`) and show `PriceInRobux`; hard-coded UI prices show the wrong number while the player is charged the regional price. Use the Dynamic Price Check tool (up to 5 test accounts; "price pinned" or "location pinned") to find hard-coded prices.
- Protect gifts and trades between players with different price levels with `MarketplaceService:GetUsersPriceLevelsAsync`.
- Price optimization tests need roughly 60,000 transactions in the previous 30 days; a test runs about 3 weeks, applies new prices only if total revenue goes up, and repeats at least every 90 days.
- Product design: passes for permanent perks, developer products for repeatable items, subscriptions for recurring value, a free path for every core feature, contextual purchase prompts at natural moments (production/game-design/contextual-purchases, monetization-foundations).
- Paid random items: disclose in the questionnaire, show odds, check PolicyService per player.

## 6. Analytics and experiments
- Built-in dashboards: acquisition (incl. Home Recommendations tab with benchmark games), engagement, retention, monetization, performance, crashes, error reports, alerts, feedback, demographics.
- Custom events: economy events (every currency source/sink), funnel events (onboarding and shop; one step per tutorial step), custom events with custom fields. Plan them before launch so the first players' data isn't lost.
- **Experiments** (production/experiments): A/B tests on configs (in-game) or matchmaking; 14-60 days; up to two variants + control for in-game experiments; pick a goal metric, all metrics are tracked; watch the minimum detectable effect; prefer one variant vs control at 50/50 on a large rollout. Use for onboarding, shop visibility, starter packs, difficulty.

## 7. Ads Manager (production/promotion/ads-manager)
- Requirements: age 13+, verified email. Pay by card (18+, $1 temporary hold) or Robux converted to ad credits (13+, minimum 1 credit, irreversible). Group games supported (group ad account; "Configure and spend group revenue" permission for group funds).
- Objectives: **Plays** (most players likely to start a session; good for testing and to help recommendations learn), **Earnings** (limited availability; likely spenders), **Engagement** (age-checked highly engaged players who count toward the Kids and Select threshold; higher cost per play; doesn't auto-pause when the threshold is reached).
- Audiences: All, New (never played or 180+ days), Recent (played in 30 days; needs 10,000+ recent players), Lapsed (30-180 days; needs 20,000+ lapsed players); advanced targeting by location, age, gender, genre, device.
- Daily or lifetime budget, start date/time, duration; auto-reload for ad credits; payment method fixed after publishing. Up to 10 thumbnails per campaign (16:9, shown evenly), from Creator Hub, uploaded, or AI-generated. Campaigns show on Home (Sponsored) and in search. Moderation usually within 24 hours.
- Non-unique games can end with no spend and no conversions.
- Remember: ad players help retrieval but don't count in the ranking stage of Recommended for You. Use ads to test thumbnails/onboarding and to seed the first cohorts, not as a substitute for retention.
- Other promotion: share links and deeplinks, referral system, invite prompts, social media links, rewarded video ads (creator 13+ and ID-verified, public game with 2,000+ unique monthly visitors, reward must be a developer product; verify current terms), immersive ad placements (production/ad-placements).

## 8. Events, update announcements, notifications
- **Experience events** (Creator Dashboard > Engagement > Events & Updates): title, subtitle, description, category, start/end, place, public/private, event thumbnails (unique ones help; up to 5). Shown on the detail page (Join Event / Notify Me), on a shareable event page, on the group page. **Trending Events in Experiences** chart needs: active event started within the last 7 days, 1,000+ RSVPs, public.
- **Update announcements**: notify opted-in players of an update with a direct join link.
- **Experience notifications**: personalized notifications to opted-in users 13+ (milestones, friend activity, timers), sent from server scripts with the Open Cloud package from the Creator Store or via the Open Cloud UserNotification API; launch data readable with `Player:GetJoinData()`; in-game permission prompts to ask for opt-in. Notification strings are created in the Creator Dashboard.
- Cadence: weekly or bi-weekly updates with one measurable goal each; plan events around weekends (Saturday peak) and holidays; test new thumbnails with each major update.

## 9. Earning programs
- Creator Rewards (since 24 July 2025): Daily Engagement Rewards and Audience Expansion Rewards (see the production plan checklist); sessions over 10 minutes matter.
- Developer Exchange (DevEx) for cashing out; 18+ DevEx rate for Robux earned from 18+ purchases (production/monetization/18-plus-devex-rate) (verify current rates before quoting numbers).
