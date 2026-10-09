# Figma -> Roblox

Roblox Studio does not open Figma files. The design is made in Figma, then either Claude reads it through the Figma MCP server and writes `ui-spec.json`, or a community plugin converts it. Either way the result is checked against `studio.md` (scale, anchors, safe areas). Research sources: Figma Community plugin pages, DevForum threads (2023-2026), Roblox Creator Hub.

## Contents
1. Setting up the Figma file
2. Figma -> Roblox mapping
3. Route A: Claude with the Figma MCP server
4. Route B: community plugins
5. Images and fonts

## 1. Setting up the Figma file
- One top-level frame per ScreenGui, 1920x1080, named exactly like the ScreenGui (`Hud`, `Shop`). Add a phone check frame (e.g. 844x390) for the HUD to see thumb zones and the top bar.
- Mark the unsafe areas on a hidden guide layer: top ~60 px (Roblox top bar at 1080p), bottom-left thumbstick and bottom-right jump zones on the phone frame.
- Layer names = Roblox instance names in PascalCase (`BuyButton`, `CoinsLabel`): controllers find them by name.
- Figma variables (colors, radii, spacing) named like the spec tokens (`Primary`, `Radius`); text styles named like spec fonts (`Heading`, `Body`).
- Buttons as components with variants Default / Hover / Pressed / Disabled; they become `:Hover` / `:Pressed` style rules and code-driven disabled states.

## 2. Figma -> Roblox mapping
| Figma | Roblox |
| --- | --- |
| Frame / group | Frame (BackgroundTransparency 1 if no fill) |
| Auto layout direction, gap | UIListLayout FillDirection, Padding |
| Auto layout padding | UIPadding |
| Auto layout alignment / space between | HorizontalAlignment, VerticalAlignment / HorizontalFlex SpaceBetween |
| Child "Fill container" | UIFlexItem FlexMode Fill |
| "Hug contents" | AutomaticSize |
| Grid of equal cards | UIGridLayout |
| Corner radius | UICorner (UDim offset in px) |
| Stroke (inside/center) | UIStroke ApplyStrokeMode Border, Thickness |
| Text stroke | UIStroke on the TextLabel (Contextual) |
| Linear gradient | UIGradient Color + Rotation (Figma angle -> Rotation, check visually) |
| Layer opacity | BackgroundTransparency / ImageTransparency / CanvasGroup GroupTransparency |
| Drop shadow | not native: offset dark frame or shadow 9-slice image |
| Background blur | not native: translucent darker panel |
| Constraints left/right/center/top/bottom | AnchorPoint + Scale position (see `studio.md` section 3) |
| Image fill / vector art | exported PNG -> ImageLabel |
| Scrolling content | ScrollingFrame + AutomaticCanvasSize |

Position and size: convert pixel boxes to Scale relative to the parent frame, AnchorPoint from the nearest third of the parent (left/center/right, top/middle/bottom), then a `UIAspectRatioConstraint` with w/h for fixed-shape elements (same rule `psd_to_spec.py` uses).

## 3. Route A: Claude with the Figma MCP server
When the Figma MCP tools are connected (tool names start with `mcp__Figma__`), follow the Figma server's own instructions: it requires loading its `figma-use` skill before `use_figma` (and `figma-generate-design` for building screens). Then:
- **Mock styles or screens in Figma**: create a file (`create_new_file`), build one frame per screen in the chosen style using the tokens from `ui-styles.md` (as Figma variables) and the mapping above, and check it with `get_screenshot`. Good for showing 2-3 style options side by side before building in Studio.
- **Read a designer's file**: `get_metadata` (layer tree, positions, sizes), `get_variable_defs` (tokens), `get_screenshot` (visual reference), `download_assets` for image exports. Write `ui-spec.json` from it with the mapping above, export raster parts into `ui/images/`, then run the normal spec -> build -> validate steps.
- Ask before creating or changing files in the user's Figma account.

## 4. Route B: community plugins
Third-party, check each one's latest version, source and issues before relying on it; all output still needs the responsive checklist in `studio.md`.
- **Figma To Roblox** (NoTwistedHere): Figma plugin that exports the selection to an `.rbxmx`, can upload images through the Open Cloud Assets API with an API key (give the key Assets read/write only, restricted to your IP; never share it). Lists unsupported effects and limited gradient support.
- **Figma Importer Assistant** (MiaGobble): paired Figma + Studio plugins, manual/automatic import, scaling tools, image mapping; open source.
- **RoImport**: paired Figma + Studio plugin, imports tagged objects, Auto Layout and rich text (newer, 2026).
- **FigBloxUI**: commercial paired plugins with automatic image upload (2026).
- **Figblox**: generates Roblox UI code (vanilla Luau or Fusion) from Figma.
- **Quick Roblox UI Exporter by Solys**: exports selected assets as organized PNGs in a ZIP (assets only, no layout).

## 5. Images and fonts
- Export only what can't be native (illustrations, icons, textured panels) as PNG @1x at the size it is shown at 1080p (@2x for small icons that must stay crisp), max 1024 px per image.
- 9-slice candidates: export at a small size with clear corners and note the corner insets for `SliceCenter`.
- Use fonts that exist on Roblox (FredokaOne, LuckiestGuy, Bangers, Michroma, Oswald, Nunito, Roboto, PressStart2P... are Google Fonts you can install for Figma; BuilderSans is Roblox's own). A Figma font that Roblox doesn't have will not survive.
