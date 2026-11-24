# Flipbook baking reference

For hero effects (a big explosion, an aura, a sword slash, a stylized fire) that a handful of `ParticleEmitter`s can't reach: build the effect in a real 3D or effects tool, render it frame by frame, pack the frames into sheets, and let Roblox play the sheets as a flipbook on one particle. Roblox can't run a Niagara, Blender or Houdini effect, but it can play pictures.

## Contents
1. When a flipbook is worth it
2. The pipeline
3. Rendering the frames (Blender, other tools)
4. Packing: `scripts/pack_flipbook.py`
5. Timing rules
6. Wiring it in Roblox
7. Reviewing and fixing
8. Budget and accessibility

## 1. When a flipbook is worth it
- Worth it: the moments players remember (ultimate, boss hit, rare drop, level-up burst), effects with a hand-made look that emitters can't give (toon fire, painted smoke, sword slashes), anything you want to look identical on every device.
- Not worth it: frequent small effects (hits, pickups, dust): `Vfx` presets are cheaper and tint to any color. A flipbook is one texture of up to 1024 px per sheet, and every sheet costs texture memory and a draw.
- Keep the set small: a few flipbooks reused across the game (recolor white-only sheets with `ParticleEmitter.Color`) beat dozens of unique ones.

## 2. The pipeline
1. **Brief**: a written description of the look, timing and size (see `vfx.md` section 9), optionally from a reference video.
2. **Build** the effect in a tool that can render a frame at a time: Blender (supported route, works with the Blender MCP server), or any other renderer. Flat, unlit-looking materials work best.
3. **Render every frame twice**, once on pure black and once on pure white (section 3).
4. **Pack** with `scripts/pack_flipbook.py`: it cuts the effect out from the difference of the two renders, scales the frames and writes 4x4 sheets plus a `.flipbook.json`.
5. **Upload** the sheets with the account or group that owns the experience; paste the ids into `Vfx.Textures`.
6. **Wire** a `Vfx` preset (section 6), **check** it in Studio, **fix** with one correction per round (section 7).

## 3. Rendering the frames
Effects are see-through and a camera can't film see-through. For a pixel with color C and opacity a, the black render is `a*C` and the white render is `a*C + (1-a)`, so `alpha = 1 - (white - black)` and `color = black / alpha`: a clean cut-out with soft glows and dark smoke intact, on any background. For that to hold, **the two renders must differ only in what the camera sees behind the effect**:

- Output **Standard** view transform (not Filmic/AgX/ACES), no dithering, no bloom or glare, 8-bit PNG, no motion blur.
- Same camera, same frames, same lighting. A white world lights the effect differently than a black one, so give the world a *fixed* lighting color for everything except camera rays (snippet below). Emission/unlit materials are immune, which is one more reason to keep these effects flat.
- Square frame, effect centered with a little margin, fixed camera (no camera moves unless the effect is meant to travel). 2x the cell size is plenty (256 px cells -> render at 512 px).
- 24 fps, 16, 32 or 48 frames (one, two or three 4x4 sheets). Start the effect on frame 1 (skip warm-up frames with `--skip-first`).

**Blender** (run through the code tool of the Blender MCP server, or in a Python console; adjust the first line):

```python
import bpy

OUT, CELL, FRAMES, FPS = "//flip", 256, 48, 24   # frames land in //flip/black and //flip/white

scene = bpy.context.scene
render = scene.render
render.resolution_x = render.resolution_y = CELL * 2   # packed down later
render.resolution_percentage = 100
render.fps = FPS
render.film_transparent = False
render.use_motion_blur = False
render.dither_intensity = 0
render.image_settings.file_format = "PNG"
render.image_settings.color_mode = "RGB"
render.image_settings.color_depth = "8"
scene.view_settings.view_transform = "Standard"
scene.view_settings.look = "None"
scene.view_settings.exposure = 0
scene.view_settings.gamma = 1
scene.frame_start, scene.frame_end = 1, FRAMES
if hasattr(scene.eevee, "use_bloom"):   # older EEVEE
    scene.eevee.use_bloom = False

# World: camera rays see a flat color (black, then white); every other ray keeps the same grey lighting.
world = scene.world or bpy.data.worlds.new("FlipbookWorld")
scene.world = world
world.use_nodes = True
nodes, links = world.node_tree.nodes, world.node_tree.links
nodes.clear()
lighting = nodes.new("ShaderNodeBackground")
lighting.inputs["Color"].default_value = (0.3, 0.3, 0.3, 1)
backdrop = nodes.new("ShaderNodeBackground")
is_camera = nodes.new("ShaderNodeLightPath")
mix = nodes.new("ShaderNodeMixShader")
output = nodes.new("ShaderNodeOutputWorld")
links.new(is_camera.outputs["Is Camera Ray"], mix.inputs["Fac"])
links.new(lighting.outputs["Background"], mix.inputs[1])
links.new(backdrop.outputs["Background"], mix.inputs[2])
links.new(mix.outputs["Shader"], output.inputs["Surface"])

for name, value in (("black", 0.0), ("white", 1.0)):
    backdrop.inputs["Color"].default_value = (value, value, value, 1)
    render.filepath = f"{OUT}/{name}/f_"
    bpy.ops.render.render(animation=True)
```

The packer's matte check is the test: if it warns about inconsistent pixels, the two renders differ by more than the background (lighting, color management or glow); switch to Cycles or make the materials emissive, then render again.

**Other tools** (Unreal Niagara, Houdini, After Effects, a game engine): same rule. Unlit or emissive materials, fixed camera, render the sequence once over a pure black background and once over pure white, same frames, no tone mapping or bloom that depends on the background. Any tool that can write the two PNG sequences works with the packer. Frames that already have a clean alpha channel (PNG with transparency) skip the double render: use `--rgba`.

## 4. Packing
```
python3 scripts/pack_flipbook.py --black flip/black --white flip/white -o flipbooks --name Blast --frames 16 --skip-first 1 --fps 24
python3 scripts/pack_flipbook.py --rgba flip/rgba -o flipbooks --name Aura --frames 16 --loop-blend 3 --color white
```
Output: `flipbooks/Blast_1.png` ... (square, power of two, up to 1024 px, 4x4 frames per sheet, row by row from the top-left) and `flipbooks/Blast.flipbook.json` with the emitter values. Options: `--grid 2|4|8`, `--sheet-size` (default 1024, frames are sheet/grid px), `--frames N` to resample, `--skip-first K`, `--loop-blend K`, `--fps`, `--fit pad|crop` for non-square renders, `--color keep|white` (white shapes get tinted by `ParticleEmitter.Color`, so one sheet serves many colors). It warns about partly empty last sheets, odd frame rates and inconsistent mattes, and exits 1 on errors. Frames of 256 px are enough for most effects; use `--grid 2` (512 px frames) only for the biggest hero effect.

## 5. Timing rules
- A flipbook plays at 20-30 frames per second. 16 frames at 24 fps is 0.67 s: right for impacts and bursts. Longer effects chain sheets: 48 frames = 3 sheets, one emitter per sheet, each starting when the previous sheet ends (`startDelay` in the JSON, `delay` in a `Vfx` preset).
- **Loops** must loop without a jump: `--loop-blend 3` cross-fades the last frames into the first. Use `FlipbookMode = Loop`.
- **One-shots**: the first rendered frame is often simulation warm-up, so start from frame 2 (`--skip-first 1`) and make the last frame empty or nearly so, then `FlipbookMode = OneShot` with a particle `Lifetime` equal to frames / fps.
- Edges that change every frame crackle and feel alive (auras, fire); edges that morph slowly look like a sticker.

## 6. Wiring it in Roblox
Per sheet, one `ParticleEmitter`: `Texture` = the sheet, `FlipbookLayout = Grid4x4` (Grid2x2 / Grid8x8 to match `--grid`), `FlipbookMode`, `FlipbookFramerate = NumberRange.new(fps)`, `Lifetime` = frames in the sheet / fps, `Speed` 0, `Rate` 0 and `Emit(1)` for one-shots, `LightInfluence = 0` for baked flat colors (so scene lighting doesn't darken them), `LightEmission` 0 to keep the baked colors (raise it only for glows), `Size` constant.

With the `Vfx` library, a preset does all of it (`FlipbookBlast` in `assets/Vfx.luau` is the template):

```lua
Blast = {
	kind = "oneshot",
	duration = 2.2, -- must outlast the last sheet: delay + lifetime
	emitters = {
		{ texture = "Blast1", burst = 1, lifetime = { 0.67, 0.67 }, speed = { 0, 0 }, size = { { 0, 9 }, { 1, 9 } },
			transparency = { { 0, 0 }, { 0.9, 0 }, { 1, 1 } }, lightInfluence = 0,
			flipbook = { layout = "Grid4x4", mode = "OneShot", fps = 24 } },
		{ texture = "Blast2", burst = 1, delay = 0.67, lifetime = { 0.67, 0.67 }, speed = { 0, 0 }, size = { { 0, 9 }, { 1, 9 } },
			transparency = { { 0, 0 }, { 0.9, 0 }, { 1, 1 } }, lightInfluence = 0,
			flipbook = { layout = "Grid4x4", mode = "OneShot", fps = 24 } },
		-- Blast3 with delay = 1.33 ...
	},
},
```
and `Vfx.Textures.Blast1 = "rbxassetid://..."` per sheet. Until a sheet is uploaded the emitter shows the engine sparkle (the flipbook settings only apply to a real texture). Server decides, clients `Vfx.play("Blast", position)` as for every effect.

**Size**: don't assume the world size of the render maps 1:1 to `ParticleEmitter.Size`. Put a reference object of known size (a 4-stud cube) in the first render, compare it with a Part of that size in Studio, and put the factor into the preset's `size`.

## 7. Reviewing and fixing
Look at a contact sheet (the packed PNG over a dark and a light background) and at the effect in Studio from the front, from behind, from above and at phone size, in a dark and a bright place. Fix **one problem per round**, in words about what you see, with the frame numbers:

| What you see | Fix |
| --- | --- |
| Edge looks spiky or like static / sound waves | "Make the edge lumpy like clouds, with holes breaking in, not spikes or noise." |
| Details turned hair-thin, lines instead of shapes | Thicken shapes, merge strands; check at phone size, not at full size. |
| Copies the reference too literally | Brief the *quality* of the reference, not its pixels ("reach this level, don't copy it"). |
| From behind it's a thin line or a flat card | Add depth: several layers, a front "shield" or arrowhead shape, sub-effects around it, or a second emitter facing the other way. |
| Gap between slash and blade (frames 12-14) | Re-lay the slash between the tip and the guard on those frames; for runtime swings use a `Trail` between two attachments at the blade tip and guard. |
| Aura much bigger or smaller than planned, edges below the floor | Size factor (section 6) and check where the pivot sits; trim the render. |
| Dark halo or fringe at the edge | Matte warning not heeded: re-render with Standard view transform and identical lighting. |

Expect 1-2 rounds for simple effects and many more for a hero effect with a complicated edge; that is normal.

## 8. Budget and accessibility
- Sheets are textures: up to 1024 px each, a few hero flipbooks in the whole game, reuse them recolored; run `roblox-security-perf-audit` on the place afterwards.
- Reduced flashing: baked frames can contain bright flashes. Mark flash-heavy emitters `flash = true` (removed with `Vfx.setReducedFlashing`), or bake a calmer variant without the full-bright first frames and play that one for players with the setting on; never leave a hero moment with no feedback at all.
- Quality: at low quality keep the flipbook (it's one particle) and drop the sub-effects around it.
- Copyright: public tutorials and videos are references for the technique and the quality level; don't trace someone's effect frame for frame, and don't upload ripped textures.
