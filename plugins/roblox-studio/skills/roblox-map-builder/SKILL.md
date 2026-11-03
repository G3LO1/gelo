---
name: "roblox-map-builder"
description: "Build and validate aesthetic, accurate and performant Roblox Studio maps (terrain, buildings, lighting presets, seeded prop scatter, procedural generation) in any style: low-poly, cartoon, realistic, horror, neon/sci-fi, fantasy, retro, PS1, cozy town. Use for any Roblox map, level, biome, lighting or 'mapa w robloxie' request."
---

# Roblox Map Builder

Goal: maps that look good AND are correct (scale, collision, navigation, performance). Process beats presets: greybox first, style second, validate always. All numbers below are starting points to playtest, not Roblox standards.

## Workflow
1. Brief: gameplay, camera + avatar, target device (phone?), STYLE, area size, landmark, time of day, existing assets/palette. Ask every decision with AskUserQuestion (multiple choice, recommended option first) rather than free text; ask only what is missing. If style unclear, propose 2-3.
2. Greybox with plain Parts on ONE grid; one landmark per zone; routes spawn -> goals; check scale vs avatar. Screenshot + playtest before detailing.
3. Terrain pass (outdoor; `references/island-recipe.md`): macro shape -> routes -> biome blending (irregular bands) -> cliffs/caves -> water. Parts/meshes for collision-critical edges.
4. Kit + dressing (scatter with `assets/Scatter.luau`; style rules in `references/styles.md`): modular pieces with shared mesh/texture IDs, palette + material rules from the style, asymmetric prop clusters, story-driven wear. Hierarchy: big shapes -> medium rhythm -> small detail.
5. Lighting pass LAST: `LightingPresets.apply` for the style, then tune against screenshots. Never use fog/bloom to hide geometry problems.
6. Validate: run `scripts/validate_map.luau`, work through the checklist below for what a script cannot decide, fix, re-run, then report briefly: what was built, what was verified, what needs a human (real phone test, uploads, manual Studio toggles).

## Studio loop
With Roblox Studio tools (execute_luau, multi_edit, insert_asset, screen_capture, start_stop_play, get_console_output, inspect_instance, search_game_tree, generate_mesh/material/texture): build -> screen_capture from player height -> playtest -> read console -> revise. Always list_roblox_studios first and confirm the target place before modifying. Inspect before editing; small reversible edits; put output under Workspace/Map/{Architecture,TerrainDetails,Props,Gameplay,Spawns}; store Seed as an attribute on Map; never touch existing user scripts without saying so.

## Custom meshes with Blender
When the style needs meshes the Studio tools can't make well (modular kit pieces, stylized trees/rocks, props), check for a connected Blender MCP server (tools with `blender` in the name; ToolSearch `blender`). If there is none, ask once whether the user has Blender and offer to connect it (`../roblox-animation-vfx/references/blender.md` section 1), or continue with parts, terrain, generate_mesh and Creator Store assets. With Blender: Roblox units and axes, pieces on the map grid with consistent pivots, <= 20,000 triangles, one material per mesh, shared textures; run `../roblox-animation-vfx/scripts/blender_check.py` (mode model) through the code tool, export, import piece by piece (3D Importer: Upload to Roblox with the owner as Creator, Insert Using Scene Position), assemble in Studio.

## Tools
All paths are relative to this skill. Run Luau files in Studio with `execute_luau` (paste the whole file), or load them as ModuleScripts.
- `scripts/validate_map.luau`: read-only validator for the checklist below. Finds missing Map structure and Seed, unanchored static parts, tiny collidable decor, precise collisions, blocked / floating / buried spawns, doors too small for the avatar (tag "Door" on the opening part), unreachable goals (tag "Goal"; PathfindingService from every spawn), floating or buried props, z-fighting (coplanar faces with different color or material), stacked post-FX, ignored fog, Neon without lights, missing streaming. Prints the report and returns it. Run it after every pass. Tag intentional movers "Dynamic" so they are not reported.
- `scripts/validate_place.luau`: the same on a `.rbxl/.rbxlx/.rbxm/.rbxmx` file: `lune run scripts/validate_place.luau <file> [--json out.json] [--fail-on high|medium|low]`. Lune has no raycasts or pathfinding: those checks are listed as SKIPPED, so run the Studio version for spawn ground, props and routes.
- `assets/LightingPresets.luau`: `LightingPresets.apply(game.Lighting, "LowPoly")` sets Lighting and post-FX for a style (LowPoly, Cartoon, Realistic, Horror, Neon, GoldenHour, Tropical, Snow, Desert, PostApoc, Retro, PS1), reuses the effects a template already put there instead of stacking new ones, and reports what it could not set. `LightingStyle` is written by name.
- `assets/Scatter.luau`: seeded scatter for trees, rocks, bushes and props: spacing, slope limit, height band, exclusion circles (spawn, landmark, path), groves, a second denser pass via `existing`. Same seed gives the same placements everywhere. `Scatter.terrainSampler(workspace, {materials = {[Enum.Material.Grass] = true}})` raycasts Terrain in Studio.
Read the findings as leads: open the instance and confirm before changing it. Thresholds are in `Validator.Thresholds` at the top of `validate_map.luau`; adjust them for the game and say so.

## References
- `references/styles.md`: per-style numbers (colors, kit sizes, lighting, scatter and wear rules). Read it when the style is chosen.
- `references/island-recipe.md`: terrain island, water, faceted trees, scatter and spawn recipe that worked in Studio.

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

## Validation checklist (before done)
Items 2, 3, 4, 5 and 10 are covered by `validate_map.luau`; the rest needs eyes, a playtest or a device.
1 Scale: avatar fits all doors/corridors, jumps match CharacterJumpHeight. 2 Seams: no gaps/z-fighting/floating/buried props; static parts anchored. 3 Collision by role. 4 Spawns on stable flat ground, clear exits, away from hazards; test first spawn AND respawn. 5 PathfindingService route spawn->every goal (tag goals "Goal"), Status Success. 6 Readability in grayscale and with post-FX off; landmark visible from spawn. 7 Test Soft + low graphics, interiors and openings separately. 8 Performance via render stats/F9/MicroProfiler on densest vista, real phone if possible. 9 Scripts tolerate streaming. 10 Organized folders, names, CollectionService tags, seed stored as attribute. 11 Playtest with start_stop_play and read get_console_output: clean.

## Common failures
Flat empty expanses; detail everywhere; mixed styles; cloned trees on a grid; doors blocking NPCs; seams/z-fighting; bloom/fog masking; template + custom post-FX stacked; giant models, unique meshes, particle vistas; "fine in editor" but untested at avatar height, low graphics, phone.

## Hand-off
Offer `roblox-security-perf-audit` for a full performance pass on the finished place (particles, shadows, NPCs, streaming), `roblox-animation-vfx` for ambient effects, and `roblox-launch-kit` for thumbnails and the store page (screenshots from player height).
