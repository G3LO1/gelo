# VFX reference

Checked against create.roblox.com/docs/effects (particle emitters, beams, trails, highlights, light sources) and performance-optimization on 9 October 2026.

## Contents
1. Feedback map: which moments need an effect
2. ParticleEmitter essentials
3. Beams, trails, highlights, lights
4. Style guide per art direction
5. Budgets and accessibility
6. Networking
7. Textures
8. Layered flipbooks

## 1. Feedback map
Every verb in the mechanic matrix gets feedback on three channels, sized by importance: **visual** (VFX, UI pop, camera), **audio** (SFX), **motion** (animation, hit-stop, shake). Big moments (level up, rare drop, purchase, boss kill) get all three and stand out; frequent moments (footsteps, coin pickup, every hit) stay small and cheap so they don't become noise.

| Moment | Vfx preset | Size |
| --- | --- | --- |
| Hit / impact | HitSpark | small, < 0.6 s |
| Pickup / collect | Pickup | small |
| Purchase | Purchase | medium, make buying feel good |
| Level up / unlock | LevelUp | big, with light |
| Heal / buff | Heal | medium |
| Footstep, landing, skid | Dust | tiny |
| Explosion | Explosion | big, with light |
| Rarity / item highlight | RarityGlow (loop) | low rate |
| Ambience | Fireflies (loop) | very low rate |
| Speed / dash | SpeedTrail (loop) | trail |
| Sword / melee swing | Slash (layered 4x4 flipbook, variants Frost / Ember) | medium, < 0.5 s |

## 2. ParticleEmitter essentials
- **Rate** is particles per second for continuous emitters; for one-shots keep `Enabled = false` and call `emitter:Emit(count)`. One emitter can create up to 400 particles/s (100/s on mobile).
- **Lifetime** (NumberRange) is capped at 20 s. **Speed** (NumberRange, studs/s) along **EmissionDirection** (NormalId of the parent) with **SpreadAngle** (Vector2 degrees). **Shape** Box/Sphere/Cylinder/Disc with ShapeStyle (Volume/Surface), ShapeInOut, ShapePartial for rings and shells.
- **Size**, **Transparency** (NumberSequence over lifetime), **Color** (ColorSequence), **Squash** (stretch along motion: sparks, rain), **Rotation/RotSpeed**, **Drag**, **Acceleration** (gravity, rising embers), **VelocityInheritance**, **LockedToPart** (particles move with the part: auras), **TimeScale** (slow-motion), **ZOffset** (draw order toward the camera), **WindAffectsDrag**.
- **LightEmission** 0 = normal blending, 1 = additive (glows, fire, magic); grayscale textures without alpha work with LightEmission 1. **LightInfluence** 0 makes particles ignore scene lighting (glows look the same day and night). **Brightness** for HDR-style punch in Realistic lighting.
- **Flipbooks**: `FlipbookLayout` Grid2x2 / Grid4x4 / Grid8x8 / Custom (FlipbookSizeX/Y), `FlipbookMode` Loop / OneShot / PingPong / Random, `FlipbookFramerate`, `FlipbookStartRandom`. Good for fire, smoke and stylized impacts.
- Particle size drives cost through fill-rate: big particles covering the screen are expensive, and overlapping transparent layers cost overdraw.

## 3. Beams, trails, highlights, lights
- **Beam**: texture stretched between two attachments (lasers, tethers, lightning, god rays); Segments + CurveSize for arcs; TextureSpeed for flow; FaceCamera for billboard beams.
- **Trail**: ribbon behind two attachments on a moving part (swords, dashes, projectiles); Lifetime short (0.1-0.4 s), WidthScale tapering to 0, MinLength to skip micro-segments.
- **Highlight**: outline/fill on a model (selection, interactables, x-ray objectives). Only 255 Highlights display at once on a client (extra ones are silently ignored, and disabled ones still take a slot), so reuse one and reparent it, and delete highlights you no longer need.
- **Lights**: PointLight/SpotLight/SurfaceLight in attachments for flashes and muzzle fire; short tween to 0; `Shadows = false` on effect lights. Neon parts don't emit light by themselves.
- **Camera**: a few studs of shake for impacts (scale by distance, respect a "reduce camera shake" setting), FOV punch for dashes.

## 4. Style guide
Match the world (see the map builder's style presets) and the UI style:
- **Cartoon / simulator**: bright saturated colors, chunky stars and circles, bouncy scale (size curve overshoot), LightEmission 0.5-1, short lifetimes.
- **Low-poly**: flat-colored square or triangle particles, few of them, no soft glows; Rotation random, no motion blur.
- **Realistic**: flipbook smoke/fire/sparks, Squash for sparks, darker smoke with LightEmission 0, dust colored from the ground material, physically plausible gravity.
- **Anime / fighting**: speed lines, impact frames (one big flash frame), ring shockwaves, hit-stop of 0.05-0.1 s, trails on every swing.
- **Horror**: almost no particles: dust motes, breath fog, flicker on one light (keep the reduced-flashing option), sound carries the feedback.
- **Sci-fi / neon**: additive glows, beams and rings in the accent colors (cyan, magenta, violet), sparks with Squash, LightInfluence 0.
- **Cozy / pastel**: soft circles, hearts, leaves, slow upward drift, low saturation and no flashes.

## 5. Budgets and accessibility
- One-shot bursts: 5-30 particles; loops: under ~60/s per emitter and only while visible; whole scene: keep the place audit's total rate warning in mind.
- Disable loops when out of view or far away (distance checks on the client), clean up one-shots (Vfx.play does).
- Quality setting: scale counts with the player's choice or device (Vfx.setQuality); low quality keeps big moments visible, drops ambience.
- Reduced flashing: no full-screen or bright flashes, no strobing lights, gentler camera shake (Vfx.setReducedFlashing removes flash emitters and lights). Offer it in settings.
- Readability: effects never hide hazards, enemies or UI; gameplay-critical telegraphs (boss attack areas) stay visible at low quality.

## 6. Networking
- Effects are client-side. The server decides what happened, then fires one remote (or `UnreliableRemoteEvent` for frequent cosmetic events) with the effect name and position/target; every client plays it with Vfx.
- The acting player's client can play its own effect immediately (prediction) and ignore the server echo for itself.
- Never create effects on the server: every particle emitter, light and tween replicates and costs bandwidth.

## 7. Textures
- `scripts/make_textures.py` generates original white-on-transparent textures (glow, star, spark, smoke, ring); `assets/textures/` holds a 128 px set. Upload them (Asset Manager bulk import) with the account or group that owns the experience and paste the ids into `Vfx.Textures`.
- 64-256 px is enough for most particles; reuse a few textures across many effects; flipbooks up to 1024 px sheets only for hero effects.
- White textures + `Color` let one texture serve every color; keep alpha soft at the edges to avoid hard squares.

## 8. Layered flipbooks
One drawing, every element: draw the effect in **white**, split into layers (glow, body, hot core; a rim if the style needs one), animate it as frames on one sheet, and let the game color each layer. `Vfx.Presets.Slash` is the worked example on its own sheet (`assets/textures/slash_4x4.png`, 16 frames: grows in, holds, tears apart along the flow).
- **Frames**: 16 on a 4x4 grid (`Grid4x4`) for most effects; 4 (2x2) for tiny ones, 64 (8x8) only for hero effects on a 1024 px sheet. The shape tapers to a point at both ends in every frame, or the ends look cut off when a frame stops. Torn edges follow the motion, never square steps.
- **Margins**: nothing within 4 px of a cell edge. Paint that touches the edge shows as a box around the effect in game. No grey smoke or haze filling the cell either ("fog machine"): it reads as squares.
- **Pack and check**: `python3 scripts/flipbook.py pack <frames-dir | anim.gif> -o sheet.png --fit --white` (same scale for every frame, white mask from colored frames), `flipbook.py check sheet.png --strict` (square, power of two, <= 1024 px, margins, empty frames, haze, white), `flipbook.py preview sheet.png -o preview.html --tint "#96d7ff" --tint "#ffb43c"` (the frame playing per color variant next to the sheet with that frame lit up; `?frame=7` opens on one frame).
- **Preset**: one emitter per layer, all on the same sheet: `layer = "Body"`, `flipbook = { layout = "Grid4x4", mode = "OneShot" }` (OneShot plays the 16 frames once over the particle lifetime; Loop/PingPong/Random use `framerate`), the same fixed `rotation` and zero speed so the layers stay stacked, `zOffset` glow < body < core, and `minQuality` on big soft layers (the glow is dropped at low quality to save fill-rate).
- **Variants**: `variants = { Frost = { Glow = {...}, Body = {...}, Core = {...} }, Ember = {...} }`, played with `Vfx.play("Slash", target, { variant = "Ember" })`; `layerColors` overrides single layers; `color` still tints everything. `Vfx.variants(name)` lists them; the showcase builds one pad per variant (`Slash_Ember`, `Slash_Frost`).
- **Accessibility**: reduced flashing turns `Random` frame jumps into `Loop`; keep bright single-frame flashes as separate `flash = true` layers so the setting can drop them.
- **Red**: keep red to glow, flame and smoke. Red drops on a slash read as blood, which the maturity questionnaire and moderation care about.
- **Upload**: the sheet goes up like any texture (owner account or group), id in `Vfx.Textures.SlashSheet`; until then the sparkle fallback shows the frames of the wrong texture, so judge the look only after upload.
