# Game UX: what the UI must do for players (and the business)

`studio.md` covers how to build UI correctly; this file covers what to build and why: information hierarchy,
attention, visual language, flows, feedback, shop and purchase moments, and the code side (UI frameworks).
Sources: Roblox creator-docs `production/game-design/ui-ux-design`, `contextual-purchases`,
`monetization-foundations`, UI docs, the RDC 2024 UI-frameworks session, and Roblox UI creators' and general game-
UI videos (list at the end). **[docs]** = Roblox docs/official talk. **[tut xN]** = N creators agree.

## 1. Five UI principles [docs]

1. **Prioritization (hierarchy of information).** Ask per screen and per moment: what is the player doing,
   what must they know or reach right now, what choices do they have, what info do those choices need, how often?
   Show only that; swap buttons by context (e.g. Sprint/Tackle without the ball, Deke/Pass with it). Small
   phone screens drown in buttons and text.
2. **Attention.** Color (vivid for what matters, muted for the rest), size, negative space, proximity (group
   related things), movement (a slight wiggle or particles for tutorial targets). In moderation: if everything
   shines, nothing does. Examples: gold stripe under premium season-pass rewards; the best-value bundle bigger and
   padded apart.
3. **Visual language.** Consistent shapes/colors per meaning (stat icons share a palette), buttons in a container
   with depth so they look pressable, headers larger and bolder than body text, legibility first. Write it down
   as a style guide (here: the ui-spec tokens and StyleSheet).
4. **Conventions.** X closes, gray = unavailable, lock icon = not unlocked yet, ProximityPrompt "E" to interact,
   number keys equip tools, circles on the ground to queue. Play the top games of the genre to learn what players
   already expect; break a convention only on purpose.
5. **Consistency.** Same meaning, same look everywhere (Health always green; close buttons always the same shape,
   color and corner; unaffordable prices always red; item names in dialogue always bold).

Test placements and HUD variants with **Experiments**; toggle platform-specific or seasonal UI live with
**Configs**. [docs]

## 2. UX: interactions and flows [docs]

- Know the players: younger audiences skew to phones/tablets; low gaming experience needs explicit hints for
  keys like C to crouch; genre veterans need less tutorial.
- Make interactions intuitive with **conventions**, **metaphors** (spells as a card deck) and **feedback**
  (hit reactions, button states, a "cha-ching" on purchase, progress bars filling). Missing feedback makes players
  think a feature is broken.
- **Flows:** list the steps to reach a goal (open avatar editor -> category -> scroll -> tap item -> Done) and
  remove friction: fewest steps, tabs and search, instant preview, tap again to remove. Sketch a flow chart per
  feature to find missing steps and pain points before building.
- "Show, don't tell": a child should understand a screen at first glance; too much text = lost players. Kids
  read less than you think. [tut x3]
- Speed beats spectacle: frequently used menus open instantly; long intro animations on menus you open often
  annoy. Gameplay UI must respond immediately and never block the action. [tut x2]
- Top developers credit their growth to "relentless obsession with user experience": broken proximity prompts,
  unpolished UI and confusing console/phone controls cost retention (one team's D1 rose after fixing console
  onboarding). [tut x2]

## 3. HUD and menus [tut + docs]

- Top bar (or a compact column) for currencies and the main menu buttons; the shop button easy to find and styled
  like the rest; everything else opens on demand. Contextual actions as ProximityPrompts. [docs + tut x3]
- One clear focal point per screen; group with spacing rather than boxes everywhere; don't clutter. [tut x3]
- Backgrounds: white with subtle detail, or semi-transparent black, leave room for strong colors on what
  matters. [tut x1]
- Pages and tabs: `UIPageLayout` gives swipe/animated page switching without code; keep a `UIPadding` so pages
  don't peek in. [tut x1]
- Progress bars with rounded ends: put the fill inside a `CanvasGroup` background so the rounded clip stays
  correct at small values. UIStroke on text: set `LineJoinMode` to Bevel or Miter to avoid overlapping corners
  on thick strokes. [tut x1]
- Diegetic UI (in the world: signs, screens, 3D prompts) can replace screen clutter and adds immersion. [tut x1]

## 4. Shop and purchase moments [docs]

- **A good shop is integrated** (easy to find, same style, quick in and out), **contextual** (explains what each
  item does and why it matters, e.g. Doors' Revives), and **inviting** (a place to browse; rotating stock and new
  items bring players back).
- Layout that converts [tut x2]: the hero item first and bigger; each item with a large image, name, one-line
  benefit, and a clear (often green) price button with the currency icon (Robux icon for Robux). Bundles and best
  value visually emphasized.
- **Contextual purchases** ("right item, right time"):
  - In-play: only where the game can pause long enough for the Robux purchase flow (e.g. a choice between rounds).
  - Pre-play: a focused shop right before a run (Doors' elevator pre-run shop for consumables).
  - Lobby: 3D displays of offers; make clear if more items exist in the main shop.
  - Complementary: offer the matching pass after one is bought (2x pollen -> 2x conversion), or bundle them.
  - UI: badges, event windows, announcements, loading screens (not on a player's very first load), and modal
    offers. Never stack modals: queue them so only one shows at a time.
- Read prices from MarketplaceService (Managed Pricing changes them per region) and show unaffordable prices in
  a consistent color (see launch-kit `launch.md`). Season passes: easy to find, clearly separate from the shop,
  free vs premium rewards visually distinct, manageable time frames.

## 5. Feedback and juice [tut + docs]

- Every press: hover/pressed states plus a tiny scale bounce (see `studio.md` Motion) and a click sound.
- Every gain: a number that counts up instead of jumping, the currency icon flying into the counter, a short pop
  and sound; big rewards get a full moment (screen dim, item reveal, particles in the UI) and still close fast.
- Make art feel tactile: identity (color, shape, type, texture) and depth (a darker copy offset under the shape,
  outside stroke, inner highlight, subtle gradient brightest at the top). Design in Figma, export images under
  1024 px, rebuild in Studio with ImageLabels/ImageButtons. [tut x2]
- Respect reduced motion and keep repeated feedback short.

## 6. The code side: UI frameworks [docs: RDC 2024 + tut x2]

- Imperative UI (clone instances, update them by hand in controllers) works for small games; the template's UI
  pattern in `roblox-luau-codegen/references/patterns.md` is this style.
- **Declarative frameworks** describe UI as a function of state and update it when state changes, which removes
  whole classes of "UI out of sync" bugs and makes reusable components (one Menu component, many menus):
  - **React Luau** (Roblox's own React port; the Roblox app is written in it; most documentation, steeper learning
    curve, not automatically fast);
  - **Fusion** (lightweight, feels closer to Roblox instances, very easy animation, more verbose);
  - **Vide** (lightweight, fine-grained updates of only what changed).
- Keep UI-only state (open tab, hover) inside components and game state (coins, inventory) in an external store
  (e.g. Charm, Reflex, or the template's DataController) that components subscribe to.
- Storybook tools (UI Labs, Hoarcekat) let you build and test components without pressing Play.
- Codify-style plugins turn Studio-built UI into framework code. Pick a framework only when the team will
  maintain it; the ui-spec -> BuildUi pipeline here produces plain instances that any approach can drive.

## 7. Checklist (add to `studio.md`'s)

1. Each screen answers "what does the player need right now?"; nothing else is visible by default.
2. One focal point per screen; attention tools used sparingly.
3. Conventions respected (X closes, gray disabled, lock = locked); same meaning = same look everywhere.
4. Every action gives feedback (visual + sound); frequent menus open instantly.
5. Shop: hero item, clear benefits, price buttons with currency icons, dynamic prices, best value emphasized.
6. Purchase prompts only at natural pauses; modals queued, never stacked; no offer on the first loading screen.
7. Flows have the fewest steps; tested by someone who has never seen the game, on a phone.

## Sources

Official: creator-docs `production/game-design/ui-ux-design`, `production/game-design/contextual-purchases`,
`production/game-design/monetization-foundations`, `ui/` (index, animation, buttons, position-and-size,
size-modifiers, 9-slice, rich-text); Roblox, "Using UI Frameworks to Conquer Code Complexity | RDC 2024" (2024-09)
https://www.youtube.com/watch?v=OHqMLEL5QnY

Creators (transcript excerpts via Perplexity; YouTube rate-limited full downloads):
- Develuper, "Make Your Roblox UI Look 10x Better" (2026-08) https://www.youtube.com/watch?v=F6AtQKo3uIY
- Stewiepfing, "Essential UI Tips & Tricks" (2024-07) https://www.youtube.com/watch?v=9kuWl_t1AOE
- ByteBlox, "Making Good UI is EASY, People Are Just Lazy" (2024-07) https://www.youtube.com/watch?v=ZTzUHfMeYKA
- Twine, "the psychology behind good ui within roblox games" (2026-10) https://www.youtube.com/watch?v=haf0V--67Ac
- Leif, "How Modern Roblox UI Actually Works" (2026-01) https://www.youtube.com/watch?v=Ezk3vEOvv8o
- Chase Higgins, "How PRO devs make UI in Roblox (Vide UI)" (2026-07) https://www.youtube.com/watch?v=p86bt9ROQfk
- Tizzy RBLX, "My Roblox Game Makes $119,300/mo (38K CCU)" (2026-07) https://www.youtube.com/watch?v=LZOohZHsJus
- Artindi, "How To Fail At UI" (2025-09) https://www.youtube.com/watch?v=ONBqAZ9KuLk
- Angelikatosh, "The Art of Game UI - Good VS Boring" (2025-04) https://www.youtube.com/watch?v=dL152bMdK0k
- Pixel Pushers, "Why Game UI Is Harder Than It Looks" (2026-03) https://www.youtube.com/watch?v=hyFMeApfyU8
- 孫拓海Taku, game UI design logic (2026-10) https://www.youtube.com/watch?v=iVBr6cGNWQo
