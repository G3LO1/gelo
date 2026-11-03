# Growth playbook: getting players and keeping the algorithm on your side

Practical tactics from developers who grew Roblox games (2024-2026 videos, list at the end), checked against
Roblox's own material: creator-docs `discovery.md`, `discovery-faq.md`, Ads Manager, analytics, onboarding,
referral and invite docs, plus Roblox's official videos (Roblox Creators channel, RDC 2026 discovery session,
interview with Roblox's Chief Growth Officer). Platform rules themselves live in `launch.md`; this file is the
how-to. **[docs]** = Roblox docs or official Roblox talk. **[tut xN]** = N independent developers agree, not
official. **[unverified]** = one claim, or contradicts nothing official but is unproven. Numbers from developers
are rules of thumb from their games and genres, not Roblox targets.

## 1. What actually decides growth [docs]

- **The game decides, the algorithm only measures.** Roblox's Chief Growth Officer: games that deliver lasting
  value (players return, play long, play with friends, choose to spend) get the most distribution. Discovery
  moved from short-term signals to 28-day windows (D1, D2-7, D8-28) in 2026.
- **Two stages.** Retrieval: plays from *any* source (ads, links, Discord, search, friends, curation) get the game
  considered; a very low number of plays is enough. Ranking: only players who arrived organically from
  Recommended for You (RFY) count: play through rate, first-play bounce (< 60 s and 61-180 s), play days and
  playtime per user (D1 / D2-7 / D8-28, playtime capped at 60 min/day), then intentional co-play days, qualified
  sessions, spend days, Robux per user. All averages per user, so small games aren't disadvantaged.
- **The click gates everything.** 99th-percentile retention with a weak icon/thumbnail still gets no
  impressions; treat packaging (title, icon, thumbnails) as part of the game. But the click must match the
  game: a misleading thumbnail raises bounce, which is a negative signal. [docs: RDC 2026]
- **A custom thumbnail is required** to receive Home recommendation impressions at all. [docs]
- **Retention or monetization alone still gets impressions; both together get the most.** If retention is low,
  fix core gameplay first; add monetization once retention holds. [docs]
- **No penalty for a weak start.** Signals use a moving window; the algorithm re-tests games with new users daily,
  so an old or failed launch can grow again after fixes. New games are judged immediately (PTR/bounce first, then
  D1, D2-7, D8-28), no 28-day wait. [docs]
- **Genre is not a ranking factor** and finite/story games aren't penalized for lower D8-28; accurate genre tags
  and a real gameplay video matter because they set expectations (fewer bounces). [docs]
- **Competition is relative.** If similar games improve faster, your impressions can fall with flat signals;
  seasonality: weekly peak Saturday, summer/back to school, holidays. [docs]
- **Coming:** Roblox is building credit for games that bring *new* players to the platform through invites,
  counting the invited friends' engagement too. Invite/referral loops are worth building now. [docs: CGO interview]
- **Video helps choice.** Hover/press-to-preview gameplay on Home made players stay significantly longer in
  games they picked; upload an honest gameplay video. A developer quotes "up to 39% more playtime" for games with a
  video [unverified figure]. [docs: CGO interview]

## 2. Packaging: title, icon, thumbnails

- **Icon:** one clear focal point, high contrast, one color that pops, a hint of intrigue; readable at 64-150 px.
  "Two-second test": show it for 2 s; if people can't say what the game is, redo it. Avoid generic AI-looking
  art. [tut x4] Official: unique, relevant, theme/tone/genre, square 512 px, preview small. [docs]
- **Thumbnails:** real gameplay framed for drama (free camera), one idea per image, little or no text (only
  gameplay context), nothing important in the bottom 15%; make many variants (10-20+) with/without text and in
  different styles. [tut x4] Iterate on the winner: clone your best thumbnail and change one element at a
  time. [tut x2] No "50% off"/"Free UGC" claims, no mechanics the game lacks. [docs]
- **Title:** short, says the hook; funny or curiosity titles can lift clicks ("Catch Me If You Can" style); no
  Robux/giveaway bait (reduced exposure). Some top studios test names by running ads to several copies of a game
  that teleport into the real one. [tut x2 + RDC 2026 panel]
- **Measure:** Home thumbnail personalization (2-5 active, measured by qualified PTR) [docs]; ads report CTR and
  play rate per creative. Developer rules of thumb for ad CTR: >= 3% good, 2-3% average, < 2% weak, < 1% change
  the icon now; play rate should be >= ~0.7x CTR. [tut x3, unverified] Packaging is "the first thing to fix"
  when CTR < ~3% in Creator Hub. [tut x1]
- **Ride trends with your own spin.** Viral games often take something people already love (memes, a popular
  mechanic) and remix it; Roblox explicitly recommends adding your own spin to trends in title, images and
  content, and demotes near-copies. [docs + tut x3]

## 3. First session and retention (what the numbers need)

Developer benchmarks (consistent across several creators; genre-dependent, verify against your Home
Recommendations benchmark games): [tut x4, unverified]

| Metric | "Probably a flop" | Healthy |
| --- | --- | --- |
| Average playtime while running ads | < 10 min | 10-15+ min |
| Average playtime once in RFY | stays at ad level | 20+ min |
| D1 retention | < 8-10% | 12-15%+ |
| D7 retention | < 1% | 2-3%+ |
| Payer conversion | | 2-3% |

- **Core loop understood in 2-5 minutes**, first reward fast, next goal reachable in another 10-15 minutes; no
  grind wall early. Official: get to the fun quickly, ideally within 5 minutes; teach controls and the core loop's
  what and why; end onboarding with a moment of joy and visible short/mid/long-term goals. [tut x3 + docs]
- **Track the funnel step by step** (funnel events per tutorial step, economy events); fix the biggest drop-off;
  A/B test onboarding variants with Experiments; tune XP thresholds and starter currency with Configs. [docs]
  One studio cut bounce substantially with an intro cutscene; another shipped nine tutorial versions. [tut x1]
- **Kids read less than you think:** show, don't explain; a missing or text-heavy tutorial kills retention. [tut x2]
- **Reasons to come back tomorrow:** offline progress ("what did I earn?"), daily rewards with a strong item on
  day 2 and day 7, a short-term target waiting at rejoin, multiple progression tracks (XP, money,
  collectibles). [tut x3] Official: goals surfaced in UI/world, season passes, quests, collections. [docs]
- **D8-28:** a mechanic that stays fun after a month (building, combat, collecting, social status), weekly updates,
  admin/community events on update days, "plan your day 8 before launch". [tut x3]
- **Friends:** co-play days are a ranking signal; invite prompts at natural moments, referral rewards for both
  sides, party/private servers. Lack of friend joins and search clicks means no word of mouth, which caps growth.
  [docs + tut x2]
- **Devices:** most players are on phones; check phone performance and touch UI; console onboarding fixes raised
  D1 for one top game (30% console players). [tut x2]
- **First 7-14 days after launch:** be in the game, watch real players, fix bugs daily, tune monetization; if the
  algorithm hasn't picked the game up by ~day 14 despite fixes, consider moving on to the next idea. [tut x2]

## 4. Ads: how developers use them [docs + tut]

Official facts: auto-bidding (you set budget and duration; Roblox sets the bid), Plays / Earnings (limited) /
Engagement objectives, unused ad credits refunded, payment method fixed after publishing; ad players help
retrieval but are excluded from RFY ranking even when they later return through Home; RFY impressions can dip
while ads run because ad-acquired users are "already acquired" (not a penalty); give campaigns several days (3-5
for Engagement) before judging. Attribution: a first play through an ad credits that ad for 30 days; a user
coming back after 7+ days is "resurrected" (7-day or 30-day credit); check Recent/Resurrected views for retention
campaigns. [docs]

Developer playbook (common pattern, amounts are what they spent, not requirements):
1. **Test packaging cheaply first:** a small campaign (roughly 5-30 ad credits) with several thumbnails to find
   the creative with the best CTR; Ads Manager serves creatives evenly, so compare per creative. [tut x5]
2. **Launch push:** Plays objective, all audiences, daily budget around 8-20 ad credits/day for about a week, 2-3+
   thumbnails; watch Acquisition > Home Recommendations for the first RFY impressions. [tut x4]
3. **Stop when organic takes over** (one creator's rule: ~50 concurrent players without ads) and put the effort
   into the next update; run ads again after a meaningful update to give the algorithm fresh cohorts. [tut x3]
4. **Fix the worst metric, then re-run small ads** to measure; one metric at a time. [tut x2]
5. **Retention campaigns** to recent players (0-30 days) around updates and events. [docs: official panel]

Reality check from creators' own reports: early campaigns often cost a few cents (USD) or several Robux per play,
ad cohorts play shorter sessions than organic players, and ads alone rarely pay back for weakly monetized games;
their value is data and the initial push. [tut x4] Old advice to set manual bids (0.01-0.5) is outdated since
auto-bidding. "Launch in beta mode so RFY doesn't judge you yet" is a claim from one creator that we could not
confirm in Roblox's docs [unverified]; the official FAQ says weak early results aren't penalized anyway.

## 5. Off-platform: short video and creators [tut]

- **Short-form video is the strongest free channel:** 10-30 s clips of the funniest, scariest or most surprising
  moment (a jump scare, a bug that's funny, a chase), captions/text hook in the first second, posted to TikTok,
  YouTube Shorts and Instagram Reels (same clip everywhere), consistently. Showcase videos can reach far beyond
  the account's follower count. Instagram pushed one dev's clips when TikTok didn't; post on all three. [tut x5]
- **Build in public before launch:** devlog clips (lighting tests, rigging, timelapses) build a Discord and a
  playtest group; one front-page shooter ran its first playtest with ~200 Discord members. [tut x3]
- **A code in the video** ("first 100 players to use code X get ...") gives viewers a reason to join right
  now. [tut x1]
- **Small creators first:** YouTubers/streamers with ~1k-20k subscribers look for new Roblox games; send a short
  pitch framed around their audience, early access and a press kit (trailer, screenshots, summary in a shared
  folder). Paid edits by TikTok editors can beat the same money in ads but cost more with reach. One YouTuber
  video took a game from ~0 to ~15 concurrent without ads, and ads after it worked better. [tut x4]
- **Split budget:** experienced devs suggest roughly half ads, half creator content once there's money; with no
  budget, make the clips yourself. [tut x2]
- **Feedback from creators is gold:** a critical YouTube review led one team to a big update that fixed what the
  community asked for. [tut x1]

## 6. Live-ops that keep growth going

- Ship fast and often: MVP first, then patches daily in the launch weeks and big updates weekly; "volume, volume,
  volume" of small tested changes beats one big gamble. [tut x3 + docs: RDC 2026 "launch an MVP, don't spend a year
  in the dark"]
- Make updates events: tease them, a sign-up stand in game (update announcements / Experience Events "Notify
  me"), a fixed update day (Friday/Saturday), admin/community events, rewards for showing up. [tut x3 + docs]
- Study top games constantly (competitor research -> data -> idea -> ship -> check stats). [tut x2]
- Each update: new thumbnail variants, one goal metric, compare cohorts (Retention > cohort table) before/after.
  [docs]

## 7. Myths vs Roblox's answers

| Heard in videos | What Roblox says |
| --- | --- |
| "Ads hurt your ranking" | No; ad users are excluded from RFY signals and a dip in RFY impressions during ads isn't a penalty. |
| "Ad players count for the algorithm" | Not for ranking; they only help retrieval (getting considered). |
| "Fail the first week and you're dead" | Moving window, daily re-testing, no penalty; old games can grow again. |
| "Pick the genre the algorithm likes" | Genre isn't a ranking factor; behaviour is. |
| "Roblox judges your first 7 days" | Since 2026: D1, D2-7 and D8-28 windows, combined and separately. |
| "Big games get favored" | Signals are per-user averages. |
| "Tags/hashtags in the description help" | Unused by ranking (see `launch.md`). |

## Sources

Official (Roblox):
- Roblox Creators, "How the Recommended for You algorithm works on Roblox" (2026-06) https://www.youtube.com/watch?v=K7jsk3bzmvE (full transcript)
- Roblox Creators, "How Home Recommendations & Ads Actually Work" (2025-10) https://www.youtube.com/watch?v=tUz_OekIIiU (excerpt)
- RDC 2026, "What Drives Discovery: Understanding the Algorithm" (2026-10) https://www.youtube.com/watch?v=bkRZeTZAvLw (excerpt)
- RDC 26 interview with Roblox's Chief Growth Officer (2026-09) https://www.youtube.com/watch?v=tabBxaWnf5g (excerpt)
- creator-docs: discovery, discovery-faq, production/promotion (ads-manager, invite-prompts, referral-system,
  experience-events, experience-notifications), production/analytics (retention, engagement, acquisition,
  funnel-events), production/game-design (onboarding, core-loops), production/publishing (thumbnails,
  experience-icons, descriptions)

Developers (transcript excerpts via Perplexity; YouTube rate-limited full downloads):
- rasdev, "the entire roblox algorithm explained in 3 minutes" (2026-06) https://www.youtube.com/watch?v=s0f09ivhir0
- rasdev, "The New Rules of the Algorithm (2026)" (2026-10) https://www.youtube.com/watch?v=RC19PKdRt1Y
- rasdev, "Give Me 15 Minutes and I'll Make You Disgustingly Good at Roblox" (2026-10) https://www.youtube.com/watch?v=DLWYPHMGfMs
- Psuedon, "How to ACTUALLY grow your Roblox game (No BS)" (2026-05) https://www.youtube.com/watch?v=hetmWWDdQlg
- VuukStudios, "My Roblox Game Hit 24,111 Players" (2026-08) https://www.youtube.com/watch?v=Tk0qXybUK0E
- MoseyTube77, "Why 90% of Roblox Games Never Get Players" (2026-08) https://www.youtube.com/watch?v=xIBc5He_sy4
- Tizzy RBLX, "My Roblox Game Makes $119,300/mo (38K CCU)" (2026-07) https://www.youtube.com/watch?v=LZOohZHsJus
- Zyonic, "How I made a FRONT PAGE game in 30 Days!" (2026-01) https://www.youtube.com/watch?v=4-ge-E9WvM4
- janisjanis01, "How I Made a Viral Roblox Game" (2026-08) https://www.youtube.com/watch?v=fjlOaEALWmg
- DevHex, "How I Make Roblox Games GO VIRAL" (2026-08) https://www.youtube.com/watch?v=Wbmw5K7-Fgk
- studio rook., "How I Made a Front Page Roblox Game... In 2 Months!" (2026-08) https://www.youtube.com/watch?v=EuaV0qc6UXQ
- ZeDarkAlien, "How To Make YOUR ROBLOX GAME Go VIRAL!" (2025-03) https://www.youtube.com/watch?v=LvEknWSArnw
- Kradez, "How Much I Spent on Roblox Ads to Hit 2k+ CCU" (2026-10) https://www.youtube.com/watch?v=lrubtajkaeI
- Kradez, "How I make HIGH CTR Roblox Thumbnails to Hit 2k+ CCU" (2026-11) https://www.youtube.com/watch?v=f-AgKj87oho
- CallMeDogey, "How to ACTUALLY Advertise Your Roblox Game" (2026-03) https://www.youtube.com/watch?v=7QfaQe4rsq8
- "I spent 400 USD on Roblox Ads" (2024-11) https://www.youtube.com/watch?v=g9UbIrR0RbU
- "I spent $5000 Robux on ads so you didn't have to" (2024-03) https://www.youtube.com/watch?v=NB8XNNDdSjQ
- SillyMan, "How to Make Your Roblox Game BLOW UP" (2024-06) https://www.youtube.com/watch?v=SjSWCIGN5PM
- ash, "Why Your Roblox Game Tutorials Suck" (2026-10) https://www.youtube.com/watch?v=BeJ0RrY6cI4
- rasyakdev, "roblox growth, for idiots like me" (2026-05) https://www.youtube.com/watch?v=q0lIbkUC2r8
- Kingkade 3D, "How To Promote Your Roblox Game" (2026-10) https://www.youtube.com/watch?v=-tgXO2XGQjU
- OKI, "3 Tricks to Make Your Roblox Game Go Viral (FOR FREE)" (2025-08) https://www.youtube.com/watch?v=58-StnYzTJE
