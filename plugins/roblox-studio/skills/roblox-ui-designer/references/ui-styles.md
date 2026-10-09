# Roblox UI styles

Starting presets for proposing a UI direction. Each gives tokens ready for `ui-spec.json`, fonts available on Roblox (`rbxasset://fonts/families/<Family>.json`; confirm in Studio's font picker), shape language, motion and where it fits. Example games show the direction, not a copy target. Research: Roblox Creator Hub art-style guidance, DevForum, current top games (2024-2026).

## Choosing
- Match genre and audience first (see `roblox-game-idea-validator` genre notes), then the game's world art: UI that fights the 3D style looks cheap.
- Propose 2-3 that fit, recommend one, say why in one line each. Mixing two styles is fine only as "base + accent" (e.g. Clean Minimal menus with Bubbly reward popups).
- Every style must still pass the mobile/readability checklist in `studio.md`.

## Contents
1. Bubbly Cartoon
2. Clean Minimal
3. Glass Modern
4. Anime / Gacha
5. Sci-fi Neon HUD
6. Horror / Grunge
7. Pixel Retro
8. Cozy Pastel
9. Competitive Minimal HUD
10. Fantasy Medieval
11. Comic Meme Pop

---

## 1. Bubbly Cartoon
Simulators, tycoons, obbies, pet/collect games, younger audience. Examples: Pet Simulator 99, Adopt Me!, most front-page simulators.
- Tokens: Primary `#FFB21E`, PrimaryHover `#FFC94D`, Secondary `#3FA9F5`, Success `#4CD964`, Danger `#FF4D5E`, Surface `#2B2F77`, SurfaceLight `#4A50B5`, Outline `#14163D`, Text `#FFFFFF`.
- Fonts: headings FredokaOne or LuckiestGuy; numbers/body BuilderSans Bold.
- Shape: big radius (16-24 px or pill `udim [1,0]`), thick dark UIStroke (4-6 px) on panels AND text, vertical UIGradient lighter on top, chunky buttons ~2x text height.
- Icons: glossy, outlined, slightly tilted; currency icons next to every number.
- Motion: pop-in scale 0.8 -> 1 with Back Out 0.2 s; button press UIScale 0.92; reward bursts with particles/confetti; number count-up tweens.
- Watch: too many colors fighting; outline on everything makes text noisy at small sizes (drop text stroke below ~18 px).

## 2. Clean Minimal
RPG menus, social/utility games, older audience, settings-heavy games. Example: Roblox's own Spellbound RPG UI tutorial.
- Tokens: Primary `#3D7BFF`, Surface `#FFFFFF` (light) or `#1C1F26` (dark), SurfaceAlt `#F2F4F7` / `#262A33`, Border `#D5DAE1` / `#343A46`, Text `#111827` / `#F3F4F6`, TextMuted `#6B7280` / `#9CA3AF`.
- Fonts: BuilderSans (Regular/Bold), GothamSSm.
- Shape: radius 8-12, 1 px stroke or none, generous padding (16-24), flat fills, no gradients.
- Icons: line icons, single color.
- Motion: 0.15-0.2 s Quad Out fades and 8-12 px slides; nothing bounces.
- Watch: can feel empty on Roblox; add one accent color and real hierarchy.

## 3. Glass Modern
Showcase/hangout, lifestyle, modern city RP, premium-feel menus.
- Tokens: Surface `#0E1220` at 0.35-0.5 BackgroundTransparency, Border `#FFFFFF` at 0.8 transparency, Accent `#7C5CFF`, Accent2 `#22D3EE`, Text `#FFFFFF`, TextMuted `#B8C0D9`.
- Fonts: BuilderSans, GothamSSm, Montserrat-like headings with GothamSSm Bold.
- Shape: radius 14-20, 1-2 px light stroke, subtle white-to-transparent UIGradient on Transparency; Roblox UI has no background blur, so fake it with darker translucent panels (or a blurred screenshot image behind menus).
- Motion: smooth 0.25 s Sine fades; CanvasGroup GroupTransparency for whole-panel fades.
- Watch: text contrast over busy 3D scenes; test outdoors at noon and at night.

## 4. Anime / Gacha
Tower defense, battlegrounds, unit collection, summon banners. Examples: Anime Defenders, Anime Adventures.
- Tokens: Surface `#121428`, Panel `#1E2245`, Gold `#FFC93C`, rarity Common `#B0B7C3`, Rare `#3FA9F5`, Epic `#A855F7`, Legendary `#FFB21E`, Mythic `#FF3D7F`, Text `#FFFFFF`.
- Fonts: headings Sarpanch, Bangers or LuckiestGuy (all caps); body BuilderSans Bold.
- Shape: angled/cut-corner frames (9-slice images), metallic gold strokes, rarity-colored glows (UIStroke + UIGradient), character art cards.
- Motion: summon reveals with flash, card flip, rarity color sweep; keep routine menus fast.
- Watch: rarity colors must be learnable and consistent everywhere; paid random items need odds displayed.

## 5. Sci-fi Neon HUD
Space, cyberpunk, futuristic shooters/racers. Pairs with the map builder's NEON preset.
- Tokens: Background `#070B14`, Panel `#0D1526` at 0.2 transparency, Cyan `#23E5F3`, Magenta `#F046C7`, Violet `#865BFF`, Amber `#FFB347`, Text `#E6F7FF`.
- Fonts: Michroma or Zekton for headings, Jura or TitilliumWeb for body, RobotoMono for numbers.
- Shape: square or 2-4 px radius, thin 1-2 px glowing strokes, corner brackets, scanline/grid images at low opacity.
- Motion: quick 0.1 s scans, flicker-in once, pulsing only for warnings.
- Watch: neon text on dark at small sizes blurs; keep body text plain light gray.

## 6. Horror / Grunge
Horror, survival, mystery. Examples: DOORS, The Mimic.
- Tokens: Background `#0B0B0C`, Panel `#18171A` at 0.15 transparency, Paper `#D8D2C4`, Blood `#8E1B1B`, Muted `#7A746A`, Text `#E8E2D5`.
- Fonts: headings Creepster (sparingly), SpecialElite or GrenzeGotisch; instructions in BuilderSans.
- Shape: torn/scratched 9-slice panels, no bright gradients, minimal HUD (hide when not needed).
- Motion: slow 0.4-0.6 s fades, rare flicker, heartbeat pulse on danger; offer reduced flashing.
- Watch: atmosphere must not hide interaction prompts and health; test on low-brightness phones.

## 7. Pixel Retro
Arcade, retro obbies, 8/16-bit themed games.
- Tokens: a fixed 8-16 color palette, e.g. Black `#1A1C2C`, Purple `#5D275D`, Red `#B13E53`, Orange `#EF7D57`, Yellow `#FFCD75`, Green `#38B764`, Blue `#3B5DC9`, White `#F4F4F4`.
- Fonts: PressStart2P for short labels and numbers; a readable second font (BuilderSans) for long text.
- Shape: square corners, 2-4 px hard borders, pixel-art images with `ResampleMode = Pixelated` and integer scaling.
- Motion: stepped movement (tween in 2-4 steps), quick flashes, no smooth easing.
- Watch: PressStart2P is wide and hard to read; keep it short and large.

## 8. Cozy Pastel
Roleplay, farming/garden, decorating, cafe/pet care, younger and casual audience. Examples: Adopt Me!, Berry Avenue, garden-style games.
- Tokens: Cream `#FFF7EC`, Peach `#FFC8A2`, Mint `#B8E6C9`, Sky `#BFE3FF`, Lavender `#D9C8FF`, Rose `#FFB3C7`, Brown `#6B4E3D` (text/outline), Accent `#FF8FA3`.
- Fonts: FredokaOne or PatrickHand/Kalam for headings, Nunito or BuilderSans for body.
- Shape: radius 16-28, soft 2-3 px brown strokes, light gradients, sticker-like icons with white outline.
- Motion: gentle bounce 0.25 s, floating idle on reward items.
- Watch: pastel on pastel kills contrast; text in dark brown, not white.

## 9. Competitive Minimal HUD
Shooters, fighting, racing, anything where reaction time matters. Examples: RIVALS, Arsenal.
- Tokens: Panel `#000000` at 0.5-0.6 transparency, Text `#FFFFFF`, Ally `#3FA9F5`, Enemy `#FF4D5E`, Warning `#FFC93C`, Health `#4CD964`.
- Fonts: Oswald or RobotoCondensed for numbers, BuilderSans for labels.
- Shape: small radius 4-6, no strokes, compact; everything at the edges, center of the screen clear except crosshair.
- Motion: instant feedback (hit markers, damage numbers), no menu animations during combat.
- Watch: on phones keep fire/ability buttons in the right-thumb zone and huge.

## 10. Fantasy Medieval
RPG, adventure, dungeon, kingdom builders.
- Tokens: Parchment `#E9D8A6`, Wood `#5C3A21`, Iron `#4A4E57`, Gold `#D4A23C`, Crimson `#9B2226`, Ink `#2B1B10`.
- Fonts: Fondamento or Merriweather headings, GrenzeGotisch for titles only, BuilderSans for numbers.
- Shape: parchment and wood 9-slice panels, gold trim strokes, ornate corners as images, ribbons for titles.
- Motion: scroll unroll, page turn, weighty 0.3 s Quad Out.
- Watch: heavy textures make phone UIs muddy; keep inventory grids plain.

## 11. Comic Meme Pop
Meme/brainrot, chaotic party games, troll obbies, short-trend games.
- Tokens: Yellow `#FFE600`, Pink `#FF4FA3`, Cyan `#00E0FF`, Black `#111111`, White `#FFFFFF`, Red `#FF3B30`.
- Fonts: Bangers or LuckiestGuy, all caps.
- Shape: thick black strokes (5-8 px), offset hard shadows (duplicate frame offset 6 px down-right in black), halftone/burst images, tilted labels (Rotation -3..3).
- Motion: shake on rewards, punchy scale 1.2 -> 1, comic "POW" bursts.
- Watch: readability collapses fast; keep core HUD calmer than the popups.
