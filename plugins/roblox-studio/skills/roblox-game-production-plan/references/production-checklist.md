# Roblox production checklist

Per-discipline tasks and current platform specs. Specs were checked against create.roblox.com and official DevForum posts in October 2026; Roblox changes them often, so re-check anything a plan depends on. Items marked (verify) were not confirmed in that check.

## Contents
1. Systems & scripting
2. Data & persistence
3. 3D models & textures
4. Characters & animation
5. UI
6. Audio
7. VFX
8. World & map
9. Monetization
10. Analytics
11. Publishing & compliance
12. QA & performance
13. Launch & live-ops
14. Commonly forgotten

## 1. Systems & scripting
- Server-authoritative design: the client sends intents ("I want to buy X"), the server checks and applies results (currency, damage, inventory, purchases). Validate every RemoteEvent/RemoteFunction argument (type, range, ownership, distance, cooldown) and rate-limit per player. Never accept instance paths or results computed by the client. Source: create.roblox.com/docs/scripting/security/client-server-boundary
- Typical system list: game state/round manager, player data module, currency/economy, inventory/items, shop, progression (levels, upgrades, rebirths), combat or interaction, NPC/enemy AI (PathfindingService), spawning, team/party, leaderboards (OrderedDataStore), settings, onboarding/tutorial, codes/rewards, admin/debug tools.
- Structure: ServerScriptService (server logic), ReplicatedStorage (shared modules, remotes), StarterPlayerScripts / StarterCharacterScripts (client), StarterGui (UI). Name and folder remotes in one place.
- Luau type checking: `--!strict` on core modules catches bugs early.
- Optional pro tooling: Rojo (files in Git), Wally (packages), Selene/StyLua (lint/format). Worth it for teams of 2+ scripters.
- StreamingEnabled: client code must handle parts that are not loaded yet (WaitForChild with timeouts, StreamingEnabled-aware loops).
- Cross-server: MessagingService (global announcements, cross-server events), MemoryStoreService (matchmaking queues, short-lived global state). Neither is permanent storage.
- Text from players (names, signs, pet names, chat-like messages) must be filtered with TextService before other players see it; use TextChatService for chat.

## 2. Data & persistence
- DataStoreService limits (per server, default): reads and writes 60 + 40 x players per minute; per-key throughput 25 MB/min read, 4 MB/min write; per value 4 MB; total storage 500 MB + 1 MB x lifetime users. Source: create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits
- Session locking so a player's data cannot be written by two servers at once (duplication exploits, rollbacks). Use a proven library (ProfileStore, community-made) or UpdateAsync with a lock field; save on leave, on BindToClose, and periodically (autosave every few minutes).
- Data schema with a version number and migration function; default values for new fields.
- Developer product receipts: grant in `MarketplaceService.ProcessReceipt` on the server, save, and only then return PurchaseGranted; make it idempotent (store processed PurchaseIds). Source: create.roblox.com/docs/production/monetization/developer-products
- Test with Studio API access enabled, and test data loss scenarios (server shutdown, rejoin quickly, two devices).

## 3. 3D models & textures
- Import: FBX, glTF, OBJ via the 3D Importer. Max 20,000 triangles per mesh; watertight, no zero-thickness faces; one material per mesh. Source: create.roblox.com/docs/art/modeling/specifications
- Textures: up to 4096x4096 upload, but budget by size: ~256 for 5-stud objects, 512 for 10-stud, 1024 for 20-stud. SurfaceAppearance (PBR on a UV-mapped mesh) up to 1024x1024 per map; MaterialVariant for tileable materials on parts/terrain. Source: create.roblox.com/docs/art/modeling/texture-specifications
- Reuse meshes and texture IDs (instances of one mesh are much cheaper than unique meshes); set CollisionFidelity per role (Box/Hull for most props), RenderFidelity Automatic.
- Asset privacy: MeshParts, Models, Packages are Restricted by default; new accounts and groups have Asset Privacy on, so new images and meshes are Restricted too. The experience must have permission to load each restricted asset (granted automatically when an editor inserts it in Studio). Upload assets to the account or group that owns the experience. Source: create.roblox.com/docs/projects/assets/privacy
- Model list for the plan: player tools/weapons, items/collectibles, NPCs/enemies, vehicles, buildings/kit pieces, props, pets, UI 3D previews (ViewportFrame), lobby/hub. Note LODs only for huge meshes.
- Creator Store (Toolbox) assets save time but inspect them for hidden scripts and wrong scale.

## 4. Characters & animation
- Decide early: players' own R15 avatars (most common, needs animations that work on any body), a custom StarterCharacter (model named StarterCharacter in StarterPlayer; full control, loses avatar self-expression), or R6 (simpler, retro, fewer joints). Animations made for R15 don't play on R6 and the other way round.
- Animation Editor in Studio (or Blender/Moon Animator, then import). Every animated rig needs an Animator (inside Humanoid or AnimationController for non-humanoid NPCs).
- Priorities: Core < Idle < Movement < Action < Action2 < Action3 < Action4. Attacks/emotes use Action+ so they override walking.
- Permissions (changed July 2025): animations are always Restricted and cannot be Open Use. The experience must have permission for each animation: upload them to the account/group that owns the experience, insert or playtest them as an editor, or add the IDs under Creator Hub > experience > Configure > Permissions > Assets. "Publish to Roblox as" copies permissions; other workflows may not, which breaks animations in production. Source: devforum.roblox.com/t/improving-animation-asset-permissions/3852101
- Animation list per character: idle, walk, run, jump, fall, climb, swim (or override the default Animate script in StarterCharacterScripts), plus every action from the mechanic matrix (attack combo, hit reaction, death, use/interact, carry, tool equip/idle, emotes, victory). NPCs: idle, walk, attack, hit, death, special.
- Animation events (markers) drive hit timing, footsteps and VFX instead of guessing with wait().

## 5. UI
- Screens: loading, main HUD (currency, health, objectives), menu, shop (passes + products), inventory, settings (music/SFX volume, graphics, reduced flashing), daily rewards/codes, onboarding prompts, notifications/toasts, death/round end, leaderboard, trading if any, confirm dialogs.
- Phone-first: scale with Scale sizes + UIAspectRatioConstraint/UIScale, big touch targets, nothing under the jump button or the top bar; respect ScreenGui.ScreenInsets (device safe area). Test in the Studio device emulator at small phone, tablet and 1080p.
- Inputs: touch, keyboard+mouse, gamepad (console). Use ContextActionService or the Input Action System for bindings and on-screen buttons.
- Localization: put strings through the LocalizationTable; Automatic Translation can translate, but review key languages (Spanish, Portuguese, etc. are large Roblox audiences).
- UI art: icons, buttons, frames, fonts (Roblox fonts), consistent style kit; images are assets with the same privacy rules as above.

## 6. Audio
- Creator Store has over 100,000 licensed free sound effects and music tracks: the fastest legal source.
- Own uploads: .mp3/.ogg/.wav/.flac, under 20 MB and 7 minutes, up to 48 kHz; 100 uploads per 30 days unverified, 2,000 if ID-verified. You must own the rights. Audio is always Restricted; grant the experience permission. Source: create.roblox.com/docs/audio/assets
- List: music per area/state (menu, gameplay, tension, victory), UI sounds (click, buy, error, reward), every mechanic from the matrix, ambience loops, footsteps by material, NPC/enemy sounds.
- Mix with SoundGroups (Music, SFX, UI) tied to the settings sliders; positional sounds for 3D events.

## 7. VFX
- ParticleEmitters, Beams, Trails, Highlights, tweens. Effects for hits, pickups, level up, purchases (make buying feel good), rarity glows, environment (dust, fireflies).
- Budget particle rates (lower on phones), reuse textures, turn emitters off when not visible. Offer a reduced-flashing option.

## 8. World & map
- Lobby/hub, gameplay areas, spawn points, boundaries/kill bricks, shop/NPC locations, landmark. Greybox first. Hand detailed map work to the `roblox-map-builder` skill.

## 9. Monetization
- Passes (one-time, permanent perks), developer products (repeatable: currency, boosts, revives) handled with ProcessReceipt, subscriptions (recurring benefits, need verified account; verify current terms), paid private servers, avatar/UGC tie-ins. Roblox keeps 30% of passes and products.
- Creator Rewards replaced Premium Payouts and Engagement-Based Payouts on 24 July 2025: Daily Engagement Rewards (5 Robux when an Active Spender plays 10+ minutes and the game is among their first three of the day) and Audience Expansion Rewards (35% of a new or returning user's first $100 of purchases in 60 days, needs 100+ average DAU, ID verification and DevEx). Session length over 10 minutes therefore matters directly. Source: devforum.roblox.com/t/introducing-creator-rewards-earn-more-by-growing-the-community/3777628
- Rewarded video ads: creator 13+ and ID-verified, public experience with 2,000+ unique monthly visitors, reward must be a developer product, disclose the ad. Source: create.roblox.com/docs/production/promotion/rewarded-video-ads
- Paid random items (crates, gacha): disclose in the maturity questionnaire, show odds, and check PolicyService (ArePaidRandomItemsRestricted, IsPaidItemTradingAllowed) per player, because some countries forbid them.
- Price testing and the price optimization tool in Creator Hub (verify availability). Plan a shop UI, purchase prompts at natural moments, and a free path for every core feature.

## 10. Analytics
- Built-in Creator Hub analytics: retention (D1/D7), session time, acquisition, monetization.
- AnalyticsService (free): LogEconomyEvent (sources/sinks of each currency, after a successful transaction), LogFunnelStepEvent (onboarding, shop; up to 10 funnels with 100 steps), LogCustomEvent (anything else), up to 3 custom fields. Dashboards appear after about 24 hours; use View Events to debug. Source: create.roblox.com/docs/production/analytics/event-types
- Plan the events at the same time as the systems: an onboarding funnel step for every tutorial step, an economy event for every currency change, a shop funnel.

## 11. Publishing & compliance
- Maturity & Compliance Questionnaire: answer accurately (violence, blood, fear, language, social hangouts, paid random items...) and update it when content changes. Labels: Minimal, Mild, Moderate, Restricted (18+ ID-verified players only; the creator must be 18+ and verified). Unrated games lose access/discovery. Source: create.roblox.com/docs/production/promotion/content-maturity
- Chat: since late 2025 players need an age check to chat and chat is split by age group; don't make the core loop depend on text chat with strangers.
- Store page: icon square 512x512 (must read at 150x150); thumbnails 16:9, 1920x1080, under 3 MB, up to 10 images/videos; gameplay video uploads limited to 3 per month and must show real gameplay. Name, description, genre, supported devices, social links. Sources: create.roblox.com/docs/production/publishing/experience-icons and /thumbnails
- Group ownership: if the game will be owned by a group, create it under the group from the start (assets, animations and audio uploaded to the group; revenue to the group).
- No third-party IP (characters, brands, music) without rights; filtered text; Community Standards.

## 12. QA & performance
- Team Test for multiplayer, Studio device emulator, then real low-end phones. Developer Console (F9) for errors and memory, MicroProfiler (Ctrl+Alt+F6) for frame spikes, render stats (Shift+F2).
- Test cases: first join, rejoin, data saving under server shutdown, purchases (test products in Studio), exploits on every remote, 1-player and full servers, slow devices, streaming.
- Private/friends test before going public; bug tracker.

## 13. Launch & live-ops
- Before launch: retention basics in place (daily rewards, goals for the next session), codes system, social links, group for updates, update log.
- Promotion: Ads Manager sponsored/search ads (small budget test of the icon first), YouTube/TikTok clips, creators. Experience notifications and events where available (verify current eligibility).
- Cadence: weekly or bi-weekly updates, limited-time events, seasonal content; each update has a measurable goal (e.g. raise D7).

## 14. Commonly forgotten
- Animation/audio/mesh permissions for the published experience (works in Studio, broken for players).
- ProcessReceipt not idempotent -> lost or duplicated purchases.
- No session locking -> item duplication.
- No BindToClose save -> data loss on server shutdown.
- UI that only works on PC.
- Questionnaire not filled -> unrated, low discovery.
- Unfiltered player text.
- Icon and thumbnails left as defaults.
- No analytics until after launch, so the first players' data is lost.
