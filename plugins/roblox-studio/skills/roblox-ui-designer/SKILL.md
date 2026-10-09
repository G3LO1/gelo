---
name: "roblox-ui-designer"
description: "Design and build Roblox game UI (HUD, shop, inventory, menus, popups, loading screens) in Figma, Photoshop or straight in Roblox Studio: proposes fitting UI styles (bubbly cartoon, clean minimal, glass, anime/gacha, sci-fi neon, horror, pixel, cozy pastel, competitive HUD, fantasy, comic meme) with ready color/font/shape tokens, designs mobile-safe layouts, converts PSDs and Figma designs, and generates a validated build script (+ .rbxmx) that creates the ScreenGuis and a StyleSheet theme in Studio. Use whenever someone wants UI, GUI, HUD, menus, buttons, a UI style or theme for a Roblox game, or asks 'zrób UI', 'jaki styl UI', 'przenieś UI z Figmy/Photoshopa do Roblox'."
---

# Roblox UI Designer

Goal: UI that fits the game's style, reads instantly on a phone, works with touch, mouse and gamepad, and ends up in Studio as clean, named, themeable instances the code can hook into. Every route (Figma, Photoshop, Studio) ends in one `ui-spec.json`, which a tested script turns into the real UI, so the result doesn't depend on which tool the designer likes.

Answer in the user's language; instance names, tokens and code stay in English.

## 1. Inputs
- Take the screens from the plan (`PRODUCTION_PLAN.md` UI tasks) or the conversation: which screens, what each must show and do, which are MVP.
- Ask once, with AskUserQuestion, only what is missing: where the UI will be designed (**Studio directly** = recommended default when there is no designer; **Figma**; **Photoshop**), existing art/brand/logo, platforms (phone-first unless told otherwise).
- Read the game's genre, audience and world art style from the plan or the map style; the UI must match them.

## 2. Style direction
Read `references/ui-styles.md`. Pick 2-3 styles that fit genre + audience + world art, recommend one, and present each in a few lines: mood, palette swatches (hex), fonts, shape language, one example game. Let the user choose (AskUserQuestion with the recommended option first).

To show rather than tell, build a style tile for the chosen style (or for each candidate): copy `assets/examples/style-tile-bubbly.json`, swap tokens/fonts/shape values for the style, and build it in Studio (or mock it in Figma when the Figma MCP server is connected, see `references/figma.md`).

## 3. Design the screens
For each screen write down before drawing anything: purpose, elements (with names), states (default, empty, loading, error, locked/owned), how it opens/closes, and which elements code drives (labels, buttons, lists). Then lay it out following `references/studio.md` (safe areas, thumb zones, anchors, scale, aspect constraints, text sizes). Names are the contract with the code: `CoinsLabel`, `BuyButton`, `ItemList`.

## 4. Build through the chosen route
Work in a `ui/` folder in the project: `ui/ui-spec.json`, `ui/images/`, `ui/BuildUi.luau`, `ui/<Name>.rbxmx`. The spec format is in `references/ui-spec.md`.
- **Studio directly**: write `ui-spec.json` yourself (tokens from the chosen style, `styles` for button states and shared looks, screens as designed).
- **Figma**: follow `references/figma.md` (Claude reads or builds the file through the Figma MCP server, or a community plugin converts it). Ask before creating or editing files in the user's Figma.
- **Photoshop**: follow `references/photoshop.md`; run `scripts/psd_to_spec.py` on the PSD, then add tokens/styles to the generated spec.

Then for every route:
1. `python3 scripts/spec_to_luau.py ui/ui-spec.json -o ui/BuildUi.luau` (checks structure and token/font/image references). Treat every `warning:` as a bug to fix: they flag layouts that are valid Roblox but render wrong, above all zero-sized elements (constraints only shrink; `SizeConstraint RelativeYY` makes width = X.Scale x parent height, so X.Scale 0 means width 0).
2. If Lune is available: `lune run scripts/validate_ui.luau ui/BuildUi.luau ui/<Name>.rbxmx` checks every property name, type and enum against Roblox's real API database and writes a model file. Fix and repeat until it prints OK. Without Lune, say that this check was skipped; Studio will report the same errors when the script runs.
3. Look at it: `python3 scripts/preview_ui.py ui/ui-spec.json -o ui/preview.html --images ui/images` renders an approximate browser preview of every screen at 1920x1080, a phone (844x390) and a tablet, with the Roblox top bar and phone thumb zones drawn on top. Take screenshots (Playwright: `npx playwright screenshot --viewport-size "844, 390" "file:///.../preview.html?screen=Hud&w=844&h=390" hud-phone.png`, or open the file in a browser) and look at them: overlaps, invisible or tiny elements, text overflow, things under the thumb zones. Fonts and text fitting are approximate; Studio is the final check.
4. Get it into Studio: with Roblox Studio MCP tools, `list_roblox_studios`, confirm the place, run `BuildUi.luau` with `execute_luau`, then `screen_capture` to look at it (desktop and a phone size in the Device Emulator if possible) and fix what looks wrong. Without MCP: the user runs `BuildUi.luau` in the Command Bar or drags in the `.rbxmx`.

The build script never deletes: a ScreenGui with the same name is kept as `<Name>_Backup` (disabled).

## 5. Check
Go through the checklist at the end of `references/studio.md`. Don't claim the UI looks right on phones unless a screenshot or emulator check actually happened; list what still needs a human eye.

## 6. Hand-off
- Images to upload (Asset Manager > Bulk Import) and where their IDs go (`images` in the spec, then rebuild); no `rbxassetid://0` may ship. Item/shop icons rendered from 3D models: with a connected Blender MCP server Claude can render them with one camera/light/outline setup for all items (`../roblox-animation-vfx/references/blender.md` section 8); otherwise ViewportFrames in the UI or renders by the team.
- The element names and tags the code should use; offer `roblox-luau-codegen` to write the controllers (UI pattern in its `references/patterns.md`: bind by name, `DataController.OnChanged`, `Net.fire`).
- Tokens live in `ReplicatedStorage.UIStyles.<Name>`: editing them in the Style Editor restyles the game (themes, events).
