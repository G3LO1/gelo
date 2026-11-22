# ui-spec format

One JSON file describes the UI; every pipeline (Studio, Figma, Photoshop) ends in it. `scripts/spec_to_luau.py` turns it into a build script, `scripts/validate_ui.luau` checks it against Roblox's real class/property database. Full examples: `assets/examples/style-tile-bubbly.json` (a style tile) and `assets/examples/components.json` (layered `ItemCard` and `Button` in all four states, with `motion`, transitions, 9-slice and the layer images in `assets/examples/images/`).

## Top level
```json
{
  "name": "FoodTruckUI",            // identifier; also the StyleSheet name
  "reference": [1920, 1080],        // design resolution (informational)
  "parent": "StarterGui",           // optional service to build into
  "tokens": { "Primary": { "color": "#FFB21E" }, "Radius": { "udim": [0, 16] } },
  "fonts": { "Heading": { "family": "FredokaOne", "weight": "Regular" } },
  "images": { "coin": "rbxassetid://0" },
  "motion": { "hoverScale": 1.04, "pressScale": 0.98, "hoverTime": 0.12 },
  "styles": [ { "selector": "TextButton:Hover", "props": { "BackgroundColor3": { "token": "PrimaryHover" } },
                "transition": { "time": { "token": "MotionHoverTime" }, "easing": "Quad", "direction": "Out" } } ],
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
- Selectors (Roblox UI styling, released Jan 2026): `TextButton` (class), `.Danger` (tag), `#BuyButton` (name), `ImageLabel#Glow` (class + name), `TextButton:Hover` / `:Press` / `:NonInteractable` (state, the `Enum.GuiState` names), `TextButton::UICorner` (the button's UICorner child), `.Panel > TextButton` (direct child), `.Panel >> TextLabel` (any descendant), `A, B` (list). `spec_to_luau.py` rejects unknown states (`:Pressed`, `:Selected`) and spaces used as combinators.
- Style rules override properties set on elements, so put shared looks in rules and one-offs in props.
- `transition` on a rule: its properties tween to the new values (`StyleRule:SetDefaultPropertyTransition`); `time` is seconds or a token, `easing` an `Enum.EasingStyle` name, `direction` In/Out/InOut.

## Motion
`motion` holds the shared animation numbers; each becomes a token `Motion<Key>` (`hoverScale` -> `$MotionHoverScale`) on the StyleSheet, usable in props, rules and transitions, and read by `assets/UiStates.luau` at runtime. Missing keys get the defaults; values outside the range are spec errors.

| Key | Default | Range | Used for |
| --- | --- | --- | --- |
| `hoverScale` / `pressScale` | 1.04 / 0.98 | 1-1.15 / 0.85-1 | `UIScale.Scale` when focused / pressed |
| `hoverTime` / `pressTime` | 0.12 / 0.08 | s | transitions into focused / pressed |
| `openTime` / `stagger` | 0.3 / 0.05 | s | window pop-in, delay between components |
| `glowIdle` / `glowFocused` / `glowPressed` | 1 / 0.35 / 0.15 | 0-1 | glow layer `ImageTransparency` per state |
| `disabledTransparency` | 0.5 | 0-0.9 | text and icon when disabled |
| `breathe` | 1.6 | 0-5 s | glow swell period while focused (0 = off) |

## Components and states
Interactive components (`assets/examples/components.json`): a transparent `ImageButton` tagged `Button` or `ItemCard` holding white layers (`Glow`, `Base`/`Glass`, `Edge`, `ItemGlow`, `Icon`, labels), each tinted with `ImageColor3`, 9-sliced where it stretches. `assets/UiStates.luau` (client) tags each component `StateFocused`, `StatePressed` or `StateDisabled` (attribute `Disabled = true`) from mouse, touch and gamepad input, and style rules like `.StateFocused > ImageLabel#Glow` or `.StatePressed > UIScale` give each state its look. A state gallery in the spec carries the tags statically, so the build, the preview and the game show the same states.

## Commands
```
python3 scripts/spec_to_luau.py ui/ui-spec.json -o ui/BuildUi.luau --images ui/images  # structure, references, selectors, motion, 9-slice
lune run scripts/validate_ui.luau ui/BuildUi.luau ui/FoodTruckUI.rbxmx  # property/type/enum checks + model file
```
Run `BuildUi.luau` in Studio (Command Bar, or the Studio MCP `execute_luau` tool) to build into StarterGui; an existing ScreenGui with the same name is renamed `<Name>_Backup` and disabled. The `.rbxmx` can be dragged into Studio or synced by Rojo, but it contains no style rule values (Lune can't write them); elements still carry their resolved look.
