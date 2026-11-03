# Running the production: team, hiring, money, collaboration

The plan says *what* to build; this file is about *how a Roblox team gets it built*: documents and boards,
definition of done, work order, hiring and paying freelancers, groups and payouts, Studio collaboration and AI
help. Sources: Roblox creator-docs (collaboration, groups, packages, DevEx, Assistant) and developer/studio videos
(list at the end). **[docs]** = Roblox docs. **[tut xN]** = N creators agree. **(verify)** = not confirmed in docs.

## 1. Documents and boards [tut x5]

- **Game design document (GDD)**, short: concept in a few sentences with reference images and links to inspiring
  games, core loop, modes and mechanics, controls and UI, monetization (passes, products), what makes it different,
  and the full asset list (builds, models, systems, animations, sounds) with who owns each. `PRODUCTION_PLAN.md`
  from this skill is the GDD's task half; keep both in the repo or a shared doc.
- **Task board** (Trello, Notion, GitHub Projects, Jira; `tasks.csv` imports): one list per discipline (scripting,
  building, modeling, UI, animation, audio) or per milestone; each card says exactly what is needed, with pictures.
- **Definition of done** on every card (a checklist: "weapon system done = equips on phone/PC/console, server hit
  check, cooldown UI, sounds, analytics event, tested with 2 players"), and a **definition of ready** (art and
  specs exist before someone starts). "Done" can't be vibes. [tut x1]
- **Scope of work (SOW)** agreed up front with every contractor: deliverables, deadline, revisions, price. Managing
  scope is the project owner's job. [tut x2]

## 2. Work order and cadence [tut x4 + docs]

- **Phase 1: art and UI for the core loop first** (models, builds, UI screens), then **phase 2: the programmer**
  brings the loop to life with real assets instead of rebuilding around placeholders later. (Greybox still comes
  first for layout: `roblox-map-builder`.) [tut x2]
- **Short cycles:** 1-2 week sprints with a build each week, a fixed **testing window** every week, smoke tests
  (a checklist of basics: join, save, buy, rejoin, phone controls) before each release. [tut x3]
- **Daily or every-other-day updates** from each person on their cards; agreed working days and hours; a clear
  boundary when someone misses agreed deadlines. Accountability, not micromanagement. [tut x2]
- **Same or overlapping time zones** for the core team make quick questions possible. [tut x1]
- **Typical timelines:** a lean MVP in 2-4 weeks for a small team (`roblox-game-idea-validator` idea-sourcing.md);
  studio projects for brands about 4-6 months from GDD to launch. [tut x2]
- **Avoid burnout:** take breaks, set deadlines per task rather than one distant release date, keep it fun for
  hobby teams; unfinished games earn nothing. [tut x1]

## 3. Hiring and paying freelancers [tut x5]

- **Where:** developer Discord communities (job boards with posting rules; prices differ a lot between servers),
  Roblox **Talent Hub** (official; filter by skill, full-time/part-time/commission, Robux/USD; prefer verified
  users), X/Twitter (many established devs), Fiverr/Upwork (more structure, check experience).
- **Vetting:** the 3 best games or pieces they worked on with links, what exactly *they* did in each, no free
  models passed off as work; a **small paid test task** before a big one.
- **Agree up front:** scope with references (images for builds, a video or spec for systems), timeline and
  milestone dates, number of revisions and the cost of extra changes, communication channel and hours, payment
  terms (often milestone-based for big jobs).
- **Payment types:** fixed price in Robux or USD (most common), hourly for long work, **percentage** of revenue only
  with teams that can show a track record: most percentage deals never pay because most games never launch, and
  many dev communities restrict them. Robux paid through a pass/group payout is subject to Roblox's fees (a pass
  sale keeps 70% for the seller), so price that in. Rush jobs cost more.
- **Red flags:** insisting on "friends and family" payments (no buyer protection), no portfolio, endless excuses,
  stolen or free-model work, pressure to pay everything up front for unproven people; report bad actors to the
  community they came from.
- Write everything down (a simple contract or message thread with the SOW) and decide **ownership of assets and
  code** in it: work for hire uploaded to the game's group.

## 4. Groups, permissions and money [docs]

- Create the game under a **group** (100 Robux) when more than one person will share revenue or edit; upload all
  assets, animations and audio to the group (production-checklist section 11).
- **Roles** in hierarchy order with permissions in General, Creation and Community categories; role managers,
  game managers, group revenue managers and DataStore deleters need **2-step verification**. Grant Edit per role
  across all group games or per game (e.g. temporarily for an FX artist before release).
- **Group payouts** of group funds to members (one-time or recurring percentage) are how teams split revenue
  (verify current payout options and holds in Creator Hub before promising terms).
- **DevEx** (cash-out) [docs]: minimum 30,000 Earned Robux; standard rate 0.0038 USD per Earned Robux (about $114 per
  30,000) since 5 Sep 2025, a higher 0.0054 rate for certain purchases by age-verified 18+ US players in eligible
  games; older balances cash out first at the old 0.0035 rate. Budget plans and payouts on what DevEx actually pays.

## 5. Collaborating in Studio [docs + tut]

- **Team Create:** everyone with Edit permission works in the same place live; collaborators show with colors and
  selection highlights; comments for feedback. For user-owned games only friends can get Edit; group games use
  roles. [docs]
- **Age-based collaboration rules:** after an age check, creators collaborate with compatible age groups by default;
  under-13 creators need trusted-friend status or parental permission to work with older creators. Plan team
  membership around this; affected people keep Edit access but may not join sessions. [docs]
- **Packages** for anything reused (modular kits, UI templates, SurfaceAppearances): edit once, update every copy and
  every place. [docs]
- **Code in Git** with Rojo for teams with 2+ scripters (branches, reviews, history), assets stay in Studio
  (production-checklist section 1, `roblox-luau-codegen/references/architecture.md`). [tut x3]
- Keep backups/version history before big changes; one person owns publishing.

## 6. AI in production (2026) [docs + tut x2]

- **Roblox Assistant** in Studio: creates and modifies objects and scripts, explains code, generates materials,
  meshes and procedural models, automates bulk property changes, and can look at the viewport through a screen
  capture subagent; chats are per place. Third-party clients (like Claude Code through MCP) get the same Studio
  tools. [docs]
- Teams use AI to prototype the core loop before a programmer scales it, and to speed up repetitive work; plan
  review time for AI-written code (security checklist, `roblox-security-perf-audit`) and keep human ownership of
  art direction. [tut x2]

## Sources

Official: creator-docs `projects/collaboration`, `projects/groups`, `projects/assets/packages`,
`production/monetization/developer-exchange`, `assistant/guide`.

Videos (transcript excerpts via Perplexity):
- SmartyRBX, "The Truth About Roblox Dev Teams Nobody Talks About" (2026-04) https://www.youtube.com/watch?v=xMr9BpJAwSQ
- Tizzy RBLX, "How to pump out high quality Roblox games FAST" (2026-05) https://www.youtube.com/watch?v=7tYPvXYlif8
- "How to Develop & Advertise Roblox Games FAST" (2026-10) https://www.youtube.com/watch?v=KYjj12-GXRs
- Meegle, "A-Z of Launching a Roblox Game" (2025-02) https://www.youtube.com/watch?v=TrrclZRHMkQ
- Open World Tycoons, "How Do Big Roblox Studios Run Their Operations Behind The Scenes?" (2025-10) https://www.youtube.com/watch?v=x8UD2H10QaU
- "How To Plan A Roblox Game - And Actually Finish It." (2022-09) https://www.youtube.com/watch?v=fxZ8Qv91LbY
- "How to Hire Roblox Developers (Without Getting Burned in 2026)" (2026-04) https://www.youtube.com/watch?v=hyQzvbzWn40
- SmartyRBX, "How To HIRE DEVS For Your Roblox Game..." (2023-01) https://www.youtube.com/watch?v=hDvnAsLaCTA
- "Hiring a Roblox Developer: Your Ultimate Guide" (2024-02) https://www.youtube.com/watch?v=DMaFMByEvI8
- "Don't Hire These Roblox Developers" (2024-09) https://www.youtube.com/watch?v=sobI4uka1p4
- "How To Find And Use The Roblox Talent Hub" (2024-09) https://www.youtube.com/watch?v=o19ctVPnM7U
