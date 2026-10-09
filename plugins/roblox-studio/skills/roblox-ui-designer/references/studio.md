# Building UI in Roblox Studio

Rules for UI that works on phones, tablets, PC and console, plus how this skill gets the UI into Studio. Sources: create.roblox.com/docs/ui (layouts, flex, styling, on-screen containers, position and size), DevForum (UI styling full release, Jan 2026).

## Contents
1. Getting the UI into Studio
2. ScreenGui setup and safe areas
3. Size, position and scaling
4. Layout
5. Look: corners, strokes, gradients, 9-slice, images
6. Styling system (StyleSheet)
7. Text and fonts
8. Mobile, gamepad and accessibility
9. Motion
10. Checklist

## 1. Getting the UI into Studio
- **Build script** (best): `spec_to_luau.py` output, run with the Studio MCP `execute_luau` tool (call `list_roblox_studios` first and confirm the place) or pasted into the Command Bar. Creates live StyleSheet rules. Re-running keeps the previous version as `<Name>_Backup` (disabled); delete backups when happy.
- **.rbxmx model** from `validate_ui.luau`: drag into Studio, or put it in a Rojo-synced folder (e.g. `"StarterGui": { "$path": "ui/screens" }`). No style rule values inside; tokens are already resolved on the elements.
- After building, check with the Studio MCP `screen_capture` (or a playtest) at desktop and phone sizes in the Device Emulator.
- Code: controllers (from `roblox-luau-codegen`) find elements by name in `PlayerGui`; never rebuild layout in code that designers maintain in Studio.

## 2. ScreenGui setup and safe areas
- `ResetOnSpawn = false` (UI survives respawn), `ZIndexBehavior = Sibling`.
- `ScreenInsets = CoreUISafeInsets` for anything interactive: keeps it clear of the Roblox top bar and notches. `DeviceSafeInsets` for full-bleed visuals that may sit under the top bar. `None` only for backgrounds/vignettes.
- One ScreenGui per independent layer (HUD, menus, popups, loading) so they can be enabled separately; `DisplayOrder` decides which is on top.

## 3. Size, position and scaling
- Position and size in Scale, not Offset, so the UI follows the screen. Offset only for small fixed things (stroke widths, paddings, gaps).
- `AnchorPoint` matching the edge an element belongs to: top-left HUD (0,0), top-right (1,0), bottom-center (0.5,1), centered popups (0.5,0.5). Then a different aspect ratio keeps it in place.
- `UIAspectRatioConstraint` on anything with a fixed shape (icons, cards, buttons, panels). Default AspectType FitWithinMaxSize keeps it inside its Scale box on every screen.
- `UISizeConstraint` to cap panels on huge monitors; `AutomaticSize` for containers that grow with content.
- Never leave an axis at zero (`Size` scale and offset both 0) expecting a constraint to fill it: `UIAspectRatioConstraint` only shrinks an element to fit its box, it never grows a zero axis. `SizeConstraint = RelativeYY` makes the width `X.Scale x parent height` (so square icons in a row: `Size = (1, 0, 1, 0)` + RelativeYY, not `(0, 0, 1, 0)`).
- Lists inside a `ScrollingFrame` with `AutomaticCanvasSize`: give items an Offset height (`UDim2.new(1, 0, 0, 120)`, scaled globally with a `UIScale`) or `AutomaticSize = Y`; Scale heights there are relative to the growing canvas. Grids: `UIGridLayout` with a `UIAspectRatioConstraint` child keeps cells square at any width.
- Design reference 1920x1080; check 16:9, 19.5:9 phones (landscape), 4:3 tablets.

## 4. Layout
- `UIListLayout` for rows/columns; `Padding` for gaps, `SortOrder = LayoutOrder`, alignment properties for placement. Flex: `HorizontalFlex` / `VerticalFlex` (Fill, SpaceBetween, SpaceAround, SpaceEvenly), `Wraps` for wrapping rows, `ItemLineAlignment`; a `UIFlexItem` child with `FlexMode` Fill/Grow/Shrink/Custom makes one item flexible.
- `UIGridLayout` for inventories/shops (`CellSize` in Scale + `UIAspectRatioConstraint` on cells); `UIPadding` for inner spacing.
- `ScrollingFrame` with `AutomaticCanvasSize` for long lists; `ScrollBarThickness` 6-8.
- Layouts own their children's position (and size with flex): don't set those by hand on laid-out children.

## 5. Look: corners, strokes, gradients, 9-slice, images
- `UICorner.CornerRadius`: `UDim(0, px)` for fixed rounding, `UDim(1, 0)` for pills/circles.
- `UIStroke`: `ApplyStrokeMode = Border` on frames/buttons, `Contextual` (default) on text for outlines; `LineJoinMode` Round for soft looks.
- `UIGradient`: `Color` (ColorSequence), `Transparency` (NumberSequence), `Rotation` (90 = top to bottom).
- Drop shadows: no native shadow. Use a duplicate dark frame offset a few px behind (hard comic shadow) or a soft shadow 9-slice image.
- 9-slice: `ScaleType = Slice`, `SliceCenter = Rect(left, top, right, bottom)` in source pixels, `SliceScale` to resize the corners. Use for panels and buttons that change size.
- Images: PNG with transparency; keep each image <= 1024 px (memory on phones; uploads accept larger); sprite sheets via `ImageRectOffset`/`ImageRectSize`; pixel art with `ResampleMode = Pixelated`.
- Upload: Studio Asset Manager (Bulk Import) or Creator Hub; new accounts have Asset Privacy on, so images are Restricted and the experience needs permission (automatic when an editor inserts them in Studio). Images pass moderation before players see them.
- `CanvasGroup` for fading or tinting a whole panel at once (costs extra memory; don't use for everything). `ViewportFrame` for 3D item/pet previews.

## 6. Styling system (StyleSheet)
Released for live games in January 2026. The build script creates it from `tokens` and `styles`:
- `StyleSheet` holds tokens as attributes and `StyleRule` children; `StyleLink` (child of a ScreenGui, `StyleSheet` property) applies it; `StyleDerive` inherits another sheet (e.g. a base theme + a seasonal theme).
- Rule `Selector`: `TextButton`, `.Tag`, `#Name`, `:Hover`, `:Pressed`, `::UICorner`, `A > B`; `Priority` breaks ties; `SetProperty` / `SetProperties` set values, `"$Token"` references a token.
- Use it for themes (light/dark, seasonal events), button states, and keeping colors consistent. Designers can then edit tokens in Studio's Style Editor.

## 7. Text and fonts
- `FontFace = Font.new("rbxasset://fonts/families/<Family>.json", Enum.FontWeight.X, Enum.FontStyle.Normal)`. Families seen on Roblox: BuilderSans, GothamSSm, SourceSansPro, FredokaOne, LuckiestGuy, Bangers, Creepster, Michroma, Zekton, Jura, TitilliumWeb, Sarpanch, Oswald, Roboto, RobotoCondensed, RobotoMono, Nunito, Ubuntu, Arimo, PressStart2P, SpecialElite, GrenzeGotisch, Fondamento, Merriweather, DenkOne, PatrickHand, Kalam, AmaticSC, IndieFlower, PermanentMarker, JosefinSans. Confirm in the Studio font picker; a wrong family silently falls back.
- `TextScaled = true` + `UITextSizeConstraint` (MinTextSize ~14 on phones, MaxTextSize at the design size) so text fits every screen; or fixed `TextSize` + `AutomaticSize` for paragraphs.
- `RichText` for inline color/bold (`<b>`, `<font color="#FFB21E">`).
- Leave room for translation (German/Portuguese run ~30% longer); never bake text into images unless it is a logo.

## 8. Mobile, gamepad and accessibility
- Thumb zones: bottom-left is the movement thumbstick, bottom-right the jump button; put frequent actions near the right thumb (around the jump button), never under either control.
- Touch targets: big. As a rule of thumb at least ~44-48 px on a phone screen and spaced apart; check in the Device Emulator on the smallest phone.
- Show only what matters during play; open the rest on demand; use ProximityPrompts for context actions instead of permanent buttons.
- Gamepad/console: every button `Selectable`, a sensible `NextSelection*` chain, `GuiService.SelectedObject` set when a menu opens; `Activated` events work for touch, mouse and gamepad.
- Contrast: body text >= 4.5:1 against its background; don't rely on color alone (rarity also needs a label/icon).
- Settings: music/SFX volume, reduced motion/flashing, UI scale (`UIScale` on a root frame).

## 9. Motion
- `TweenService` with short durations: buttons 0.08-0.12 s, panels 0.15-0.25 s, rewards up to 0.4 s.
- Press feedback: `UIScale` 1 -> 0.92 -> 1; hover (PC) lighten via `:Hover` style rule.
- Pop-in: scale 0.8 -> 1 with `Enum.EasingStyle.Back`, Out; fade with `GroupTransparency` on CanvasGroups.
- Respect the reduced-motion setting: skip bounces and shakes.

## 10. Checklist
1. Everything interactive inside `CoreUISafeInsets`; nothing under thumbstick/jump.
2. Scale-based layout + AnchorPoints + aspect constraints; tested at 16:9, 19.5:9, 4:3 in the emulator.
3. Text readable at the smallest phone (>= 14 px), contrast OK, translations fit.
4. Every button has hover/pressed feedback and works with gamepad selection.
5. Images uploaded, approved, permitted for the experience; no `rbxassetid://0` left.
6. Names match what the controllers expect; no leftover `_Backup` ScreenGuis.
7. One style used consistently (tokens), reward/hype moments stand out from routine UI.
