# Photoshop -> Roblox

Photoshop has no Roblox exporter, so this skill ships one: `scripts/psd_to_spec.py` reads the PSD (psd-tools), exports each visual layer as a trimmed PNG and writes `ui-spec.json` with positions converted to Roblox Scale/AnchorPoint. Editable text stays text. Research: psd-tools docs, Adobe UXP docs, DevForum workflows, community Photoshop MCP projects (2025-2026).

## Contents
1. Document setup
2. Layer conventions
3. Export and build
4. What doesn't convert
5. Claude driving Photoshop (MCP)

## 1. Document setup
- 1920x1080 px, RGB 8-bit, 72 ppi: the canvas is the reference screen.
- Guides: top ~60 px for the Roblox top bar; on a phone mock, bottom-left thumbstick and bottom-right jump areas. Put guides/notes in a group tagged `#skip`.
- Fonts: use fonts Roblox has (see `studio.md` section 7) so text layers map 1:1; others fall back to BuilderSans (the script prints the mapping).

## 2. Layer conventions
- Top-level group = one ScreenGui (`HUD`, `Shop Menu` -> `Shop_Menu`). Loose top-level layers go into a `Main` ScreenGui.
- Nested group = Frame. Pixel, shape, smart-object and fill layers = ImageLabel with their own PNG. Text layers = TextLabel (font, size, color and alignment read from the layer).
- Tags in layer names (removed from the Roblox name):

| Tag | Effect |
| --- | --- |
| `#button` | group -> ImageButton (children inside), image -> ImageButton, text -> TextButton |
| `#slice=N` or `#slice=L,T,R,B` | 9-slice image, N px corners stay fixed while it stretches |
| `#list-v=GAP` / `#list-h=GAP` | group children in a UIListLayout, ordered by position |
| `#scroll` | group -> ScrollingFrame |
| `#raster` | export a text layer as an image (logos, heavily styled titles) |
| `#skip` | ignore (guides, notes, mock backgrounds, screenshots of the game) |

- Hidden layers are ignored. Names should be the instance names the code will use (`Buy Button #button` -> `Buy_Button`; better `BuyButton #button`).
- Button states: separate layers/groups per state (`BuyButton`, `BuyButtonPressed #skip` as reference) or one image + style rules for hover/pressed tint.

## 3. Export and build
```
pip install psd-tools
python3 scripts/psd_to_spec.py design.psd -o ui --name ShopUI
# upload ui/images/*.png (Studio Asset Manager > Bulk Import), put each rbxassetid into "images" in ui/ui-spec.json
python3 scripts/spec_to_luau.py ui/ui-spec.json -o ui/BuildUi.luau
lune run scripts/validate_ui.luau ui/BuildUi.luau ui/ShopUI.rbxmx
```
Then add tokens/styles to the spec if the UI should be themeable, and run `BuildUi.luau` in Studio.

Positions: each element is placed in Scale relative to its parent, anchored to the nearest third of the parent (so top-right stays top-right on phones), with a `UIAspectRatioConstraint` keeping its shape (except 9-slice images and near full-size panels). Text gets `TextScaled` with `UITextSizeConstraint.MaxTextSize` = its Photoshop size.

## 4. What doesn't convert
- Layer styles (drop shadow, bevel, glow, stroke) may not render in the exported PNG: psd-tools is not Photoshop's renderer. For styled layers, convert to a smart object and rasterize (or merge) before export, or tag text with `#raster`. Text strokes are better rebuilt as UIStroke in the spec.
- Blend modes, adjustment layers and masks on groups: flatten what matters into pixel layers.
- Text effects, tracking and multiple styles inside one text layer: only the first style run is read.
- Exact pixel layout on every screen: the output is responsive (Scale), so check it in the Device Emulator and fix anchors where needed.

## 5. Claude driving Photoshop (MCP)
There is no official Adobe MCP server. Community ones exist, e.g. `mikechambers/adb-mcp` (UXP plugin + proxy), `alisaitteke/photoshop-mcp` (ExtendScript via AppleScript/COM), `StarBoze/Photoshop-MCP-Server`. They are third-party code that controls the user's Photoshop: only suggest them, never install them without the user asking. If one is connected, Claude can build the PSD mock following the conventions above, then run the export script on the saved file.
