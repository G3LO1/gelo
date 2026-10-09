# ui-spec format

One JSON file describes the UI; every pipeline (Studio, Figma, Photoshop) ends in it. `scripts/spec_to_luau.py` turns it into a build script, `scripts/validate_ui.luau` checks it against Roblox's real class/property database. Full example: `assets/examples/style-tile-bubbly.json`.

## Top level
```json
{
  "name": "FoodTruckUI",            // identifier; also the StyleSheet name
  "reference": [1920, 1080],        // design resolution (informational)
  "parent": "StarterGui",           // optional service to build into
  "tokens": { "Primary": { "color": "#FFB21E" }, "Radius": { "udim": [0, 16] } },
  "fonts": { "Heading": { "family": "FredokaOne", "weight": "Regular" } },
  "images": { "coin": "rbxassetid://0" },
  "styles": [ { "selector": "TextButton:Hover", "props": { "BackgroundColor3": { "token": "PrimaryHover" } } } ],
  "screens": [ { "class": "ScreenGui", "name": "Hud", "props": {}, "children": [] } ]
}
```
(Comments above are for reading only; JSON has none.)

## Nodes
`{ "class": "Frame", "name": "Panel", "props": {...}, "children": [...], "tags": ["Card"], "attributes": {...} }`
- `class`: any Roblox class (Frame, TextLabel, TextButton, ImageLabel, ImageButton, ScrollingFrame, CanvasGroup, ViewportFrame, UICorner, UIStroke, UIGradient, UIPadding, UIListLayout, UIGridLayout, UIFlexItem, UIAspectRatioConstraint, UISizeConstraint, UITextSizeConstraint, UIScale...).
- `name`: becomes `Instance.Name`. Names are the contract with the code: controllers find elements by name, so use stable PascalCase names (`BuyButton`, `CoinsLabel`).
- `tags`: CollectionService tags; style selectors `.Tag` match them.
- Screens must be ScreenGui / SurfaceGui / BillboardGui. Recommended ScreenGui props: `ResetOnSpawn: false`, `ZIndexBehavior: Sibling`, `ScreenInsets: CoreUISafeInsets`.

## Values
Plain numbers, booleans and strings are used as-is. Everything else is a one-key object:

| Encoding | Example | Roblox type |
| --- | --- | --- |
| `udim2` | `{ "udim2": [0.5, 0, 0.1, 0] }` | UDim2 (xScale, xOffset, yScale, yOffset) |
| `udim` | `{ "udim": [0, 12] }` | UDim |
| `vector2` | `{ "vector2": [0.5, 0.5] }` | Vector2 |
| `rect` | `{ "rect": [24, 24, 104, 104] }` | Rect (SliceCenter) |
| `color` | `{ "color": "#FFB21E" }` | Color3 |
| `token` | `{ "token": "Primary" }` | the token's value |
| `enum` | `{ "enum": "ScaleType.Slice" }` | EnumItem |
| `font` | `{ "font": "Heading" }` or `{ "font": { "family": "LuckiestGuy", "weight": "Bold" } }` | Font (`rbxasset://fonts/families/<family>.json`) |
| `image` | `{ "image": "coin" }` | the content ID from `images` |
| `colorseq` | `{ "colorseq": [[0, "#FFFFFF"], [1, "#000000"]] }` | ColorSequence |
| `numseq` | `{ "numseq": [[0, 0], [1, 0.6]] }` | NumberSequence |

## Tokens and styles
- Tokens are the design system: colors, radii, gaps. Element props reference them with `{ "token": "Name" }`; the builder resolves them, so the UI looks right even without styles.
- The builder also creates `ReplicatedStorage.UIStyles.<name>` (a StyleSheet holding the tokens as attributes) and a `StyleLink` in every ScreenGui. `styles` rules keep token references live (`"$Primary"`), so changing a token in the Style Editor restyles the whole UI.
- Selectors (Roblox UI styling, released Jan 2026): `TextButton` (class), `.Danger` (tag), `#BuyButton` (name), `TextButton:Hover` / `:Pressed` (state), `TextButton::UICorner` (the button's UICorner child), `.Panel > TextButton` (direct child).
- Style rules override properties set on elements, so put shared looks in rules and one-offs in props.

## Commands
```
python3 scripts/spec_to_luau.py ui/ui-spec.json -o ui/BuildUi.luau     # structure + reference checks
lune run scripts/validate_ui.luau ui/BuildUi.luau ui/FoodTruckUI.rbxmx  # property/type/enum checks + model file
```
Run `BuildUi.luau` in Studio (Command Bar, or the Studio MCP `execute_luau` tool) to build into StarterGui; an existing ScreenGui with the same name is renamed `<Name>_Backup` and disabled. The `.rbxmx` can be dragged into Studio or synced by Rojo, but it contains no style rule values (Lune can't write them); elements still carry their resolved look.
