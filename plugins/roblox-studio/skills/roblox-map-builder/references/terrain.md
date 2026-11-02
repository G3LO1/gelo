# Terrain pass: workflow, tools, techniques, scripts

Distilled from 16 Roblox terrain/environment tutorials (2023-2026, list at the end) and checked against Roblox's
creator docs (`Roblox/creator-docs`: Terrain class, Terrain Editor, Environmental terrain, Custom terrain
materials, Materials, performance guide). **[docs]** = stated by Roblox docs. **[tut xN]** = consistent advice
from N tutorials. **[unverified]** = single claim, test before relying on it.

## 1. Order of work

1. **Purpose and reference first.** What the terrain does for play (route, visibility, pace, mood: desert = exposed,
   forest = hidden secrets, snow = slow and isolated) and 1-3 photo/game references (Pinterest, ArtStation, real
   photos). "Form" references give shapes, "style" references give the look. [tut x6]
2. **Block out.** Rough shapes in Parts (Part to Terrain plugin, or the script in section 6) or Generate/Import,
   at avatar scale with a rig placed for sizing. Leave room behind the play area for a "facade": cliffs and
   hills that close the scene and hint at a world beyond; the player must not see the map edge. [tut x4]
3. **Convert, then normalize.** Turn the blockout into terrain, then remove every straight line with Sculpt/
   Smooth/Flatten: nature has no straight edges, but don't flatten everything either. [tut x5]
4. **Materials by logic.** Grass on flat tops, Rock/Slate/Basalt on steep faces, Sand at the water line,
   Ground/Mud on paths and between other materials. Recolor materials to one palette. [tut x5]
5. **Water**, then **gray-box buildings/bridges** to reserve space, then **rocks** on cliff edges and shores,
   then **trees** (groves, mixed sizes), then **small plants** where color is needed or seams must be hidden.
   [tut x3]
6. **Lighting early, tuned at the end** (`lighting.md`): terrain that reads at noon can lose all depth at dusk;
   test sky/bloom/sun while building. [tut x2]
7. **Detail where the player looks.** Spend the budget on paths, landmarks and the player's camera angle; keep
   the background loose or behind fog. Check from player height, not the editor bird's-eye view. [tut x4]

## 2. Editor tools and facts [docs]

- Voxels are 4x4x4 studs, each with a material and an occupancy 0-1; occupancy makes neighbors morph smoothly.
- **Create tab:** Import (heightmap + optional colormap), Generate (biomes Arctic, Dunes, Canyons, Lavascape,
  Water, Mountains, Hills, Plains, Marsh; Blending, Caves, Biome Size, Seed), Clear (whole place!).
- **Edit tab:** Select (Ctrl+C/V/X/D, Delete on a region), Transform (move/rotate/scale a region; Merge Empty;
  Live Edit), Fill (fill or Replace material in a region), Sea Level (Create / Evaporate water in a region),
  Draw, Sculpt (has Strength 0.1-1), Smooth, Flatten (Erode to Flat / Grow to Flat / Flatten All, Fixed plane),
  Paint (Paint or Replace mode).
- Brushes: sphere/box/cylinder, size 1-64, Pivot bottom/center/top, Plane Lock (Auto follows camera, Manual =
  set plane), Ignore Water, Ignore Parts, Auto Material. **Ctrl** = subtract, **Shift** = smooth while drawing/
  sculpting, **B** + drag/scroll = size, **Ctrl+B** = height, **Shift+B** = strength, **Alt+click** = material
  picker.
- **Heightmap import:** 1 pixel = 4 studs, max 4096x4096, .png/.jpg; brightness = height; the selection's Y size
  sets the range (Y 128: black = 64 below center, white = 64 above). Colormaps must use the exact colors of
  Roblox's color key with hard edges (no anti-aliasing), otherwise the nearest material is picked.
- **Grass blades** only grow on `Grass` (not LeafyGrass/Ground). Terrain.Decoration on, GrassLength 0.1-1, both
  Studio-only (NotScriptable); sway from global wind (Workspace wind direction/speed); Reduce Motion slows it.
- **Material colors:** Terrain.MaterialColors in Properties, or `Terrain:SetMaterialColor()` from code (global per
  material).
- **Water:** WaterColor (default dark teal), WaterTransparency 0-1 (default 0.3), WaterReflectance 0-1 (default 1),
  WaterWaveSize 0-1 studs, WaterWaveSpeed 0-100. Some water properties only show in playtest unless Editor Quality
  Level is at max.
- **Custom textures:** MaterialVariant in MaterialService with base material = the terrain material, then set
  it as that material's override in MaterialService (global for that base material, parts included). TerrainDetail
  instances give separate top/side/bottom textures. Physical properties of a variant apply to terrain too.
- **Expanded Terrain (2026):** Workspace > Expanded Terrain = Enabled (place restarts) gives up to **62 custom
  paintable terrain materials** (each = base material + color + optional MaterialVariant, made from the Terrain
  Editor material picker "+", managed in the Terrain Materials Manager), so several grass shades can coexist
  instead of one global override. Also smaller place files and faster terrain streaming/loading. Limits: deleted
  materials show bright purple; Team Create needs exit + ~15 s before reopening; MaterialVariant physical
  properties not used yet; with a small streaming radius, **terrain thinner than 16 voxels (64 studs) can vanish
  on the client** (make it thicker; thinning saves no memory there); heightmap/colormap imports can differ.

## 3. Shaping techniques

- **Part blockout -> terrain.** Build the landform from Parts/Wedges (modular pieces, duplicated), "double slope"
  steps for smoother hills, overlapping is fine, then convert. Corner wedges and unions don't convert with the
  common plugin; use normal wedges. [tut x3]
- **Cylinder stamps.** Draw tool, cylinder brush, pivot center, snapping/plane lock off: scatter big cylinders
  then smaller ones around them, then Sculpt (small size, high strength) to fill cracks, Subtract (large, low
  strength) to knock off odd bumps, Flatten lightly, re-add. Leave only intentional cracks. [tut x1]
- **Cliffs:** square off the outer frame first, inset the face, add a lip/overhang at the top edge, model
  layered strata; real cliff photos as reference. [tut x2]
- **Shores:** sand edges with a wavy outline (wave erosion), gentle slope into water instead of a vertical drop;
  water needs a solid bed under it. [tut x2 + SKILL.md]
- **Rivers:** follow logic (where does the water come from and go), consistent width (smaller brush on bends),
  banks smoothed down to the water, close the river off out of sight. [tut x2]
- **Paths:** Ground/Mud painted through grass with small bends and occasional branches, intersections become
  detail spots (corners are the easiest places to dress). [tut x2]
- **Snow:** piles up in corners and against objects; mountains and dead trees fit the climate. **Canyons/desert:**
  red sand + rock, small cracks and bends in awkward places. **Forest:** decide dense/small/hilly first; trees in
  mixed-size groups. [tut x1]
- **Low-poly:** smooth terrain can't be faceted. Use parts/wedge triangles (a triangle/node plugin that joins
  points into wedge triangles, SmoothPlastic + flat colors), Blender meshes, or the FillBlock-column island from
  SKILL.md; terrain can still serve as a quick sculpt to trace over, then be deleted. [tut x1]
- **Real places:** download a heightmap PNG of a real area from a heightmap website and Import it (e.g. Y 512,
  X/Z 4096); smooth artifacts and set sea level after. [tut x1, import mechanics: docs]

## 4. Making it look good

- **Paint variation, not one flat material.** Spam-click small brushes of Rock into Ground, then Ground between
  the rocks, LeafyGrass speckles on Grass, Mud in low spots; let materials spill a little. Sculpt Rock with a
  small brush so stones "grow" out of the ground. [tut x2]
- **One palette.** Recolor the 3-5 materials you use so they match (darker grounds, slightly warm LeafyGrass);
  desaturate anything that glares (bright sand). Check the screenshot with a palette extractor. [tut x3]
- **LeafyGrass** has no blades: use it where blades would poke through parts/floors or for variety. [tut x1]
- **Rocks:** large, wide rocks build the cliff, small ones only refine; layer them like strata, each step slightly
  offset, sizes growing toward the cliff; rotate the same rock 90 degrees for 4 looks; no three identical rocks
  next to each other; some protrude for depth; a thin sculpt of grass over rock tops hides the seam. [tut x2]
- **Nothing floats.** Sink rocks and trees into the ground; floating props are the most common giveaway. [tut x3]
- **Trees:** groups of small/medium/large, rescale or rotate 90+ degrees when two are adjacent, don't block all
  light, put some on the outer edge so the world continues; bushes around small rocks. [tut x3]
- **Hide seams** where meshes meet terrain with ferns, small rocks, leaves, pebbles (a pebble gradient between
  dirt and stone works well). [tut x2]
- **Decals** for dirt, moss, cracks, snow build-up, paths: lightweight, but don't spam. [tut x2]
- **Guide the eye:** fallen logs, paths, light pointing to where you want players to go; a landmark visible from
  the spawn. [tut x2]
- **Mesh terrain for close-up realism.** Showcase builders use PBR meshes (SurfaceAppearance: color, normal,
  roughness, metalness maps) for rocks, ground patches and paths, and Roblox terrain only to complement them.
  "PBR Nature" packs in the Creator Store; check every pack for scripts. [tut x3]
- **Water look:** raise WaterTransparency, keep reflectance, pick the sky first (water reflects it); splash
  particles around rocks in water. A tutorial reports that decals/particles below the water surface are hidden
  unless WaterWaveSize is 0 [unverified]. Part-water (stylized): textured top surface only, stacked
  semi-transparent dark layers underneath for depth, a foam outline mesh, darker edges ("vignette"). [tut x3]

## 5. Grass beyond Terrain.Decoration

Default blades: cheap, wind-animated, color = Grass material color, GrassLength sets height and density. For a
richer look, **card grass**: 4 transparent grass images (512x512) on crossed planes (tilt the top edges, slide the
top vertices down to avoid texture bleeding), exported as FBX; in Studio: DoubleSided on, RenderFidelity
Performance, CanCollide/CanQuery/CanTouch off, CollisionFidelity Box, **CastShadow off**, SurfaceAppearance
AlphaMode Transparency + optional normal map; darker duplicates for variation; scatter with a brush plugin
(radius ~16, spacing 2-3) in separate passes per grass type so patches form. Modeled 3D blades are too heavy.
Many objects cost even at equal triangles; hills, trees and buildings hide grass behind them (occlusion
culling [docs]). [tut x1]

## 6. Scripts (run from the command bar / execute_luau in Edit mode)

**Seeded heightfield with slope-based materials and water**, written in chunks with `WriteVoxels` (regions must
be voxel-aligned, resolution 4, at most 4,194,304 voxels per call [docs]):

```lua
local Terrain = workspace.Terrain
local SEED, SIZE, MAX_H, WATER_Y = 1234, 512, 96, 20 -- studs; SIZE multiple of 256
local CHUNK = 64 -- voxels per side per WriteVoxels call
local rng = Random.new(SEED)
local ox, oz = rng:NextNumber(0, 1e4), rng:NextNumber(0, 1e4)

local function height(x: number, z: number): number
	local h, amp, freq = 0, 1, 1 / 256
	for _ = 1, 4 do -- 4 octaves of math.noise (roughly -0.5..0.5 each)
		h += amp * math.noise(x * freq + ox, z * freq + oz)
		amp *= 0.5
		freq *= 2
	end
	return math.clamp((h + 0.6) / 1.2, 0, 1) * MAX_H
end

local function material(x: number, z: number, h: number): Enum.Material
	local slope = math.max(math.abs(height(x + 4, z) - height(x - 4, z)), math.abs(height(x, z + 4) - height(x, z - 4))) / 8
	if h < WATER_Y + 2 then
		return Enum.Material.Sand
	elseif slope > 0.9 then
		return Enum.Material.Rock
	elseif slope > 0.45 then
		return Enum.Material.Ground
	end
	return Enum.Material.Grass
end

local cellsY = math.ceil((MAX_H + 8) / 4)
for cx = 0, SIZE / 4 - 1, CHUNK do
	for cz = 0, SIZE / 4 - 1, CHUNK do
		local mats, occ = {}, {}
		for i = 1, CHUNK do
			mats[i], occ[i] = {}, {}
			for j = 1, cellsY do
				mats[i][j], occ[i][j] = {}, {}
			end
			for k = 1, CHUNK do
				local x = (cx + i - 1) * 4 + 2 - SIZE / 2 -- voxel centre
				local z = (cz + k - 1) * 4 + 2 - SIZE / 2
				local h = height(x, z)
				local mat = material(x, z, h)
				for j = 1, cellsY do
					local bottom = (j - 1) * 4
					local o = math.clamp((h - bottom) / 4, 0, 1)
					if o > 0 then
						mats[i][j][k], occ[i][j][k] = mat, o
					elseif bottom < WATER_Y then
						mats[i][j][k], occ[i][j][k] = Enum.Material.Water, 1
					else
						mats[i][j][k], occ[i][j][k] = Enum.Material.Air, 0
					end
				end
			end
		end
		local min = Vector3.new(cx * 4 - SIZE / 2, 0, cz * 4 - SIZE / 2)
		Terrain:WriteVoxels(Region3.new(min, min + Vector3.new(CHUNK * 4, cellsY * 4, CHUNK * 4)), 4, mats, occ)
		task.wait() -- keep Studio responsive
	end
end
workspace:SetAttribute("TerrainSeed", SEED)
```

Then normalize by hand (Smooth/Sculpt), paint paths, and validate spawn/paths as in SKILL.md. Bigger maps: raise
SIZE and keep CHUNK so each call stays small; add a radial falloff to `height` for islands.

**Blockout parts -> terrain** (same idea as the Part to Terrain plugin; corner wedges are skipped):

```lua
local Terrain = workspace.Terrain
local folder = workspace:FindFirstChild("TerrainBlockout") -- put the blockout parts here
local DEFAULT = Enum.Material.Grass
local done = Instance.new("Folder")
done.Name = "ConvertedBlockout" -- command-bar edits aren't undoable: keep the parts instead of deleting them
done.Parent = game:GetService("ServerStorage")
for _, p in folder:GetDescendants() do
	if not p:IsA("BasePart") then
		continue
	end
	local name = p:GetAttribute("TerrainMaterial") -- optional per-part override, e.g. "Rock"
	local mat = if name then Enum.Material[name] else DEFAULT
	if p:IsA("WedgePart") then
		Terrain:FillWedge(p.CFrame, p.Size, mat)
	elseif p:IsA("Part") and p.Shape == Enum.PartType.Ball then
		Terrain:FillBall(p.Position, p.Size.X / 2, mat)
	elseif p:IsA("Part") and p.Shape == Enum.PartType.Cylinder then
		-- Part cylinders run along X; FillCylinder runs along the CFrame's Y axis
		Terrain:FillCylinder(p.CFrame * CFrame.Angles(0, 0, math.rad(90)), p.Size.X, math.min(p.Size.Y, p.Size.Z) / 2, mat)
	elseif p:IsA("Part") and p.Shape == Enum.PartType.Block then
		Terrain:FillBlock(p.CFrame, p.Size, mat)
	else
		warn("skipped", p:GetFullName(), "(unsupported shape)")
		continue
	end
	p.Parent = done
end
```

Use `Terrain:ReplaceMaterial(region, 4, from, to)` (region aligned with `Region3:ExpandToGrid(4)`) for bulk
re-materialing, `Terrain:SetMaterialColor()` for the palette.

## 7. Performance

- Terrain triangles: flat terrain is tessellated much more densely than it needs, terrain LOD can't be tuned per
  object, and terrain always collides (no CanCollide/CollisionFidelity per area) [tut x2]. Showcase builders call
  big all-terrain maps memory heavy and use meshes with LOD/RenderFidelity, CanCollide off and Box fidelity for
  non-walkable dressing [tut x2]; others find terrain fine. Measure your map (render stats, MicroProfiler,
  memory) instead of trusting either camp.
- Occlusion culling skips parts, meshes and terrain hidden behind other objects [docs]: hills, forests and buildings
  that break sightlines make dense dressing affordable; flat open fields render everything. [tut x1]
- Instance streaming + Model LevelOfDetail SLIM keeps distant models/terrain visible cheaply [docs]; don't set the
  streaming radius so small that the world pops (see Expanded Terrain thickness note). Test with streaming on.
- CastShadow off on thousands of grass/plant pieces; textures only on visible faces of part water/ground;
  dense foliage only near paths; fewer, larger rocks instead of many tiny ones. [tut x3]
- Volumetric fog meshes, 3D-blade grass and unoptimized Sketchfab models are showcase-only. [tut x3]

## Common mistakes

Straight edges and perfectly flat ground; one material everywhere; default saturated colors; floating rocks and
trees; repeated identical rocks/trees in rows or grids; detail spread evenly instead of where players look; map
edge visible; river or water with no logic; thin terrain shells vanishing under streaming; judging from the
editor camera only; no reference.

## Sources (YouTube, transcripts pulled with `tools/yt_research.py`)

- SmartyRBX, "The EASIEST Guide to Making Amazing Terrain" (2023-03) https://www.youtube.com/watch?v=CippiATeZ54
- PrizeCP Roblox, "Beginner Guide to Terrain in Roblox Studio" (2026-02) https://www.youtube.com/watch?v=HYZr6R0ePLI
- HollyHollers, "How to Make Realistic Terrain" (2026-01) https://www.youtube.com/watch?v=Ye1zLeYa7qE
- HollyHollers, "Why You SHOULDN'T Use Roblox Terrain" (2026-01) https://www.youtube.com/watch?v=YhQ_ERl4w7g
- RKGAM3ZS, "How To Make Your Terrain Better in Roblox Studio" (2025-10) https://www.youtube.com/watch?v=WoakBTSFKvA
- RKGAM3ZS, "How To Make Realistic Water in Roblox Studio" (2025-10) https://www.youtube.com/watch?v=vp83W8Ej0Us
- Tutorial Pad, "How to use terrain editor in Roblox Studio" (2025-12) https://www.youtube.com/watch?v=drcrFyAg8e0
- Tutorial Pad, "How to make a river using terrain editor" (2025-12) https://www.youtube.com/watch?v=7aVD1kSqnMI
- OKI, "Making Roblox Terrain Look Like a AAA Game in 2025" (2025-06) https://www.youtube.com/watch?v=JOF2aya6WLU
- Ice Guy, "How to Create REALISTIC GRASS in Roblox" (2026-08) https://www.youtube.com/watch?v=zMN_rP30H5Y
- BONES, "Terrain Textures" (2024-10) https://www.youtube.com/watch?v=gpsErt8wFqE
- BONES, "Environmental Art" (2024-10) https://www.youtube.com/watch?v=-DoOf32pkPo
- RoBuilder, "3 Tips to Make The PERFECT Water" (2023-12) https://www.youtube.com/watch?v=mSKJg066mbQ
- Emilki, "Turn REAL PLACE to ROBLOX Game" (2024-02) https://www.youtube.com/watch?v=U_d_PEjgoPs
- Scroof, "How to make Low Poly Terrain in ROBLOX" (2023-02) https://www.youtube.com/watch?v=gI1Oe7lSkSE
- Hibstheribs, "Realistic Forest Environment + Speedbuild" (2026-03) https://www.youtube.com/watch?v=jykvT0JlYw4
