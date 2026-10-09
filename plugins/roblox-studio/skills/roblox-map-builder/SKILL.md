---
name: "roblox-map-builder"
description: "Build aesthetic, accurate and performant Roblox Studio maps (terrain, buildings, lighting, props, procedural generation, validation) in any style: low-poly, cartoon, realistic, horror, neon/sci-fi, fantasy, retro, PS1, cozy town. Use for any Roblox map, level, biome, lighting or 'mapa w robloxie' request."
---

# Roblox Map Builder

Goal: maps that look good AND are correct (scale, collision, navigation, performance). Process beats presets: greybox first, style second, validate always. All numbers below are starting points to playtest, not Roblox standards.

## Workflow
1. Brief: gameplay, camera + avatar, target device (phone?), STYLE, area size, landmark, time of day, existing assets/palette. Ask every decision with AskUserQuestion (multiple choice, recommended option first) rather than free text; ask only what is missing. If style unclear, propose 2-3.
2. Greybox with plain Parts on ONE grid; one landmark per zone; routes spawn -> goals; check scale vs avatar. Screenshot + playtest before detailing.
3. Terrain pass (outdoor): macro shape -> routes -> biome blending (irregular bands) -> cliffs/caves -> water. Parts/meshes for collision-critical edges.
4. Kit + dressing: modular pieces with shared mesh/texture IDs, palette + material rules from the style, asymmetric prop clusters, story-driven wear. Hierarchy: big shapes -> medium rhythm -> small detail.
5. Lighting pass LAST: apply style preset, tune against screenshots. Never use fog/bloom to hide geometry problems.
6. Validate (checklist below), fix, re-check, then report briefly: what was built, what was verified, what needs a human (real phone test, uploads, manual Studio toggles).

## Studio loop
With Roblox Studio tools (execute_luau, multi_edit, insert_asset, screen_capture, start_stop_play, get_console_output, inspect_instance, search_game_tree, generate_mesh/material/texture): build -> screen_capture from player height -> playtest -> read console -> revise. Always list_roblox_studios first and confirm the target place before modifying. Inspect before editing; small reversible edits; put output under Workspace/Map/{Architecture,TerrainDetails,Props,Gameplay,Spawns}; store Seed as an attribute on Map; never touch existing user scripts without saying so.

## Custom meshes with Blender
When the style needs meshes the Studio tools can't make well (modular kit pieces, stylized trees/rocks, props), check for a connected Blender MCP server (tools with `blender` in the name; ToolSearch `blender`). If there is none, ask once whether the user has Blender and offer to connect it (`../roblox-animation-vfx/references/blender.md` section 1), or continue with parts, terrain, generate_mesh and Creator Store assets. With Blender: Roblox units and axes, pieces on the map grid with consistent pivots, <= 20,000 triangles, one material per mesh, shared textures; run `../roblox-animation-vfx/scripts/blender_check.py` (mode model) through the code tool, export, import piece by piece (3D Importer: Upload to Roblox with the owner as Creator, Insert Using Scene Position), assemble in Studio.

## Hard rules
- Use Lighting.LightingStyle (Realistic|Soft) + PrioritizeLightingQuality; Lighting.Technology is deprecated (Future=Realistic+prioritized, ShadowMap=Soft+prioritized, Voxel=Soft+not prioritized). VERIFIED: LightingStyle is script-writable via execute_luau in Edit mode.
- Atmosphere overrides legacy FogStart/FogEnd. Neon does not light anything (add Point/Surface/SpotLight). ShadowSoftness is Realistic-only. ClockTime never advances without a script. Shadows vanish below graphics level 4.
- Terrain color: Terrain:SetMaterialColor() (per material, global). Terrain.Decoration (grass blades), GrassLength (0.1-1), StreamingEnabled are Studio-side and NOT scriptable: for low-poly/cartoon tell the user to untick Decoration in Properties. MaterialVariant on terrain = global override of the base material. Terrain voxels are 4x4x4 studs.
- Place templates ship with Bloom/DepthOfField/SunRays: when applying a preset delete or merge them so template and custom effects don't stack.
- No universal part/light-count limit: budget the visible scene on a baseline device; measure (Shift+F2 render stats, F9 memory, Ctrl+Alt+F6 MicroProfiler). Illustrative only: <1000 draw calls, <1M visible tris; imported mesh max 20,000 tris.
- Procedural generation must be seeded (Random.new(seed+n), math.noise), constrained (slope, spacing, path/landmark reservations) and validated (connectivity, spawn safety, pathfinding).
- Don't recreate specific copyrighted maps/assets; use lessons only. Inspect Toolbox models for scripts and scale.

## Core numbers
- 1 stud ~ 0.28 m. Classic avatar ~5 studs, humanoid 6-6.5. Jump height default 7.2. Door ~3-3.4 x 7.3-7.7 (realistic) or 5-7 x 8-10 (game-scale); ceiling 8.6-9.6 real / 10-14 game; stair rise 0.5-1 run 2-3; lane 10.7-12.9. Pick realistic OR enlarged circulation, never mix.
- One kit grid before placing (4 or 8 residential, 16 ship/station, 32 Backrooms). Consistent lower-corner pivots. No coplanar overlapping faces. Anchor static geometry.
- Streaming start: Improved / PauseOutsideLoadedArea / MinRadius 64 / TargetRadius 1024 / Opportunistic; static chunks Model.LevelOfDetail=SLIM, modules <= ~64 studs/dim.
- Collision by role: floors/walls CanCollide true; decor CanCollide/CanTouch/CanQuery false; CollisionFidelity Box->Hull->Default->Precise (cost order); simple invisible colliders on key walkways.
- Pathfinding defaults AgentRadius 2, AgentHeight 5, WaypointSpacing 4: set for the real NPC, check Path.Status spawn->goal, recompute on Path.Blocked.
- Textures: 1024^2 = 4x memory of 512^2; <=512 for most, <256 minor. MaterialVariant = tileable PBR, SurfaceAppearance = UV mesh. Reuse asset IDs. Particles ceiling 400/s (100/s mobile), budget far lower.

## Learned in practice (low-poly island ~200x200, verified in Studio)
- Island on Terrain: delete Baseplate, FillBlock in 4-stud columns; height = radial falloff + big Gaussian hill + 2 octaves math.noise; irregular coast radius via noise on angle; materials by height/slope: Sand beach, Rock steep, Grass top, Ground along the path.
- Water: ocean ring strips PLUS a Sand seabed underneath, else hard seam at the coast.
- Faceted canopy: MANY small/medium rotated cubes in an ellipsoid, 3-4 green shades, lowest mass below the widest point. One huge cube = blocky; thin stack = lollipop. Trunk = crossed blocks + root buttresses, pivot at base, bury 0.5-1 stud.
- Scatter: raycast Terrain, Grass only, Normal.Y >= ~0.78-0.86, min spacing ~8, exclude path/landmark/spawn, grove centers. First pass is usually too sparse: do a denser second pass. Target ~75 trees / 26 rocks / 19 bushes per 200x200.
- Spawn: search the flattest spot (minimise height spread across pad corners), re-screenshot to confirm it sits flush.
- Screenshots: use player-height cameras outside canopy blocks.
- Final checks that worked: 0 unanchored parts, Pathfinding Success spawn->goal, playtest with clean console.

## Style cheat-sheet (starting presets)
LOW-POLY: SmoothPlastic, 4-6 related swatches + 1 accent, S 30-70% V 55-90%. Soft or Realistic (Realistic = sharper facets); CT 14, B 2, Ambient #697A83, OutdoorAmbient #A9C5C5, ShadowSoftness 0.35; Bloom 0.08/20/1.5; Atmosphere Density 0.12 Haze 0.2; SunRays 0.05/0.25. Faceted silhouettes decided before modeling; trees 5-8 sided trunk + angular canopy masses, 14-25 studs; one unmistakable landmark.
CARTOON/TYCOON/OBBY: Soft; CT 14, B 2.5, Ambient #9AA6B6, OutdoorAmbient #C8DDF0; Sat +0.08; Bloom 0.12/24/1.6; Atmosphere Density 0.08. One ground hue + one architecture hue + one action hue, S 45-85% V 70-95%; max saturation only for rewards/hazards/signs. Chunky bevels 0.5-2 studs; exact-edge gameplay in parts not terrain.
REALISTIC: Realistic + PrioritizeLightingQuality; CT 14, B 2.2, Exposure -0.1, ShadowSoftness 0.35, Env diffuse/specular scale 1, Ambient (55,58,62), OutdoorAmbient (118,125,132); Atmosphere Density 0.22 Haze 0.8 Color (195,210,225); Contrast 0.04 Sat -0.04; Bloom 0.12/18/1.8. PBR albedo without baked shadows, OpenGL normals, asphalt non-metallic; grid 4/8; scatter foliage in groves via raycast; no live mirror reflections. Fake-realism order of failure: scale -> silhouettes -> materials/sky -> lighting support -> noisy decals -> effects.
HORROR/BACKROOMS: Realistic; CT 0, B 1.4, Ambient (58,53,40), OutdoorAmbient (65,61,47); Atmosphere Density 0.12 Haze 0.6 Color (196,184,135); Contrast 0.04 Sat -0.12; Bloom 0.12/18/1.2. Route readable without flashlight (next decision visible 12-25 studs); 32x32 module kit; ceiling SurfaceLight 1-2 / Range 12-18 / no shadows; rare flicker on ONE fixture, reduced-flash option; positional audio (RollOff 6-35); seeded DFS room generator with door-mask templates (bits N1 E2 S4 W8) guarantees reachability only, not pacing.
NEON/CYBERPUNK/SCI-FI: Realistic; CT 0.5-2, B 1-2, Ambient #1A2030, OutdoorAmbient #30304A; Atmosphere Density 0.2-0.35 Haze 0.5-1.5; Bloom 0.2-0.45 / 20-36 / 0.85-0.95; Contrast 0.05-0.15. ~75% dark / 20% mid / 5% accent (cyan #23E5F3, magenta #F046C7, violet #865BFF, amber #FFB347). Neon only on thin strokes + real lights beside it; wet roads via roughness 0.15-0.3 puddles, metalness ~0; SurfaceGui signs LightInfluence 0, AlwaysOnTop false; street 20-32, buildings 48-160, 16-stud ship kit.
FANTASY/NATURE: layout hub -> roads -> biome entrances -> dungeon/castle; sizes: path 8-12, road 16-24, cottage 16-24 wide walls 9-12, doorway 5-7 x 8-10, wall 4-8 thick x 18-30, tower 14-24 dia x 28-50, dungeon module 16 or 32. Cobblestone/WoodPlanks/Slate/Brick. 5-12 big trees per 100x100 patch in groves, no grids; irregular biome seams via pass/river/ridge. Golden-hour: CT 17, B 2, OutdoorAmbient (145,125,105), Atmosphere Color (215,188,145) Density 0.28 Haze 1.2. Tropical CT 13 Atmosphere (183,224,212) 0.32/1.6. Snow CT 11 Sat -0.12. Desert CT 15 Haze 2.0 Sand (207,174,116). Post-apoc CT 16 B 1.3 Sat -0.35 Contrast 0.14. One Lighting per place: pick compatible baseline.
RETRO/CLASSIC: Soft, CT 14, B 1.5-2, flat grays Ambient ~(115-128), little/no bloom; Plastic/SmoothPlastic, anchored rectangular parts. BLOCKY/VOXEL: fixed 2- or 4-stud cube grid (terrain voxels are not crisp cubes). PS1: 64-256 px textures, SurfaceAppearance.ResampleMode=Pixelated, Soft, B 1, Exposure -0.2, Sat -0.18, light fog. CEL-SHADE: matte SmoothPlastic + baked 2-3 color bands, Highlight (FillTransparency 1, Occluded; limit 255) or inverted-hull outlines, don't outline everything. SPLATOON-TOON: neutral architecture + bold team colors, ink as bounded marks not unlimited decals. COZY TOWN: grid 4, bay 4/8 wide, story 9-11 high, door 5-6 x 8-9, lot 40x48..48x64, street 18-24 + 4-6 sidewalk, warm PointLight (255,210,160) Range 8-14, furnish interaction zones, Soft CT 17 B 2.

## Validation checklist (before done)
1 Scale: avatar fits all doors/corridors, jumps match CharacterJumpHeight. 2 Seams: no gaps/z-fighting/floating/buried props; static parts anchored. 3 Collision by role. 4 Spawns on stable flat ground, clear exits, away from hazards; test first spawn AND respawn. 5 PathfindingService route spawn->every goal (tag goals "Goal"), Status Success. 6 Readability in grayscale and with post-FX off; landmark visible from spawn. 7 Test Soft + low graphics, interiors and openings separately. 8 Performance via render stats/F9/MicroProfiler on densest vista, real phone if possible. 9 Scripts tolerate streaming. 10 Organized folders, names, CollectionService tags, seed stored as attribute. 11 Playtest with start_stop_play and read get_console_output: clean.

## Common failures
Flat empty expanses; detail everywhere; mixed styles; cloned trees on a grid; doors blocking NPCs; seams/z-fighting; bloom/fog masking; template + custom post-FX stacked; giant models, unique meshes, particle vistas; "fine in editor" but untested at avatar height, low graphics, phone.