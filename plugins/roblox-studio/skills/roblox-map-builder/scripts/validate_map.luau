--!nocheck
-- Map validator: the checklist items of roblox-map-builder that a script can decide.
-- Read-only: it never changes the place.
--
-- In Studio: paste this whole file into execute_luau (Roblox Studio MCP) or the Command Bar;
-- it prints the report and returns it as a string. Edit mode is fine; the raycast checks
-- (spawn on ground, floating or buried props) and the pathfinding check run there.
-- On a place/model file: lune run validate_place.luau <file.rbxl|.rbxlx|.rbxm|.rbxmx>
-- (loads this file with MAP_RETURN = true and calls Validator.run itself). Lune has no
-- raycasts or pathfinding: those checks are reported as skipped, not as passed.
--
-- Conventions it reads (all optional, each missing one is a finding, not an error):
--   Workspace.Map            root folder/model, with Architecture, TerrainDetails, Props, Gameplay, Spawns
--   Map attribute "Seed"     the seed of a procedural map
--   tag "Goal"               a part the player must be able to reach from every spawn
--   tag "Door"               an invisible Part whose Size is the clear opening (height = Y,
--                            width = the larger of X and Z)
--   tag "Dynamic"            an unanchored part on purpose (or a model with such parts)
--
-- Numbers are starting points to investigate, not Roblox limits.

local Validator = {}

Validator.Thresholds = {
	MapFolders = { "Architecture", "TerrainDetails", "Props", "Gameplay", "Spawns" },
	LooseParts = 40, -- parts directly under Map instead of in a folder
	TinyStuds = 1, -- decor smaller than this should not collide
	TinyCollidable = 100,
	PreciseCollision = 30,
	DoorMinWidth = 4.5, -- avatar ~5 studs tall, 2 wide: the opening must clear it with room
	DoorMinHeight = 7.5,
	SpawnClearance = 7, -- free studs above a spawn pad
	SpawnMaxGroundGap = 1, -- pad bottom to the ground below
	PropMaxFloat = 0.75, -- prop bottom above the ground below
	PropMaxBuried = 1.5, -- prop bottom below the ground below (0.5-1 is intended)
	RaycastProps = 400, -- how many props to raycast (the rest are not checked)
	CoplanarTolerance = 0.01,
	CoplanarMinOverlap = 0.25, -- studs of overlap on both other axes
	CoplanarMaxParts = 6000, -- skip the check on bigger maps (O(n) with a grid, but each cell scans)
	CoplanarExamples = 8,
	NoStreamingParts = 5000,
	NeonWithoutLight = 5, -- Neon parts in the map and no light at all
	Agent = { AgentRadius = 2, AgentHeight = 5, AgentCanJump = true },
	MaxGoals = 25,
}

local function get(instance, property, default)
	local ok, value = pcall(function()
		return instance[property]
	end)
	if ok and value ~= nil then
		return value
	end
	return default
end

local function path(instance)
	local ok, name = pcall(function()
		return instance:GetFullName()
	end)
	return ok and name or instance.Name
end

local function hasTag(instance, tag)
	local ok, result = pcall(function()
		return instance:HasTag(tag)
	end)
	return ok and result
end

-- Tagged "Dynamic" itself or inside a tagged ancestor.
local function isDynamic(instance, root)
	local current = instance
	while current and current ~= root do
		if hasTag(current, "Dynamic") then
			return true
		end
		current = current.Parent
	end
	return false
end

local function inCharacter(instance)
	local current = instance.Parent
	while current do
		if current:IsA("Model") and current:FindFirstChildWhichIsA("Humanoid") then
			return true
		end
		current = current.Parent
	end
	return false
end

-- World-space axis-aligned bounds of a part (exact for 90-degree rotations).
local function bounds(part)
	local cf, size = part.CFrame, part.Size
	local right, up, look = cf.RightVector, cf.UpVector, cf.LookVector
	local p = cf.Position
	local hx = (math.abs(right.X) * size.X + math.abs(up.X) * size.Y + math.abs(look.X) * size.Z) / 2
	local hy = (math.abs(right.Y) * size.X + math.abs(up.Y) * size.Y + math.abs(look.Y) * size.Z) / 2
	local hz = (math.abs(right.Z) * size.X + math.abs(up.Z) * size.Y + math.abs(look.Z) * size.Z) / 2
	return { p.X - hx, p.Y - hy, p.Z - hz, p.X + hx, p.Y + hy, p.Z + hz }
end

-- True when the part's axes line up with the world axes (so its bounds are its real faces).
local function axisAligned(part)
	local cf = part.CFrame
	local function isAxis(v)
		local ax, ay, az = math.abs(v.X), math.abs(v.Y), math.abs(v.Z)
		return math.max(ax, ay, az) > 0.999
	end
	return isAxis(cf.RightVector) and isAxis(cf.UpVector) and isAxis(cf.LookVector)
end

local function canRaycast(workspace)
	local ok, fn = pcall(function()
		return workspace.Raycast
	end)
	return ok and fn ~= nil
end

function Validator.run(game, options)
	options = options or {}
	local T = Validator.Thresholds
	local workspace = game:GetService("Workspace")
	local lighting = game:GetService("Lighting")
	local report = { findings = {}, stats = {}, skipped = {} }
	local stats = report.stats

	local function add(severity, rule, message, examples)
		table.insert(report.findings, {
			severity = severity,
			rule = rule,
			message = message,
			examples = examples or {},
		})
	end

	local function sample(list, limit)
		local out = {}
		for index = 1, math.min(#list, limit or 5) do
			out[index] = list[index]
		end
		if #list > #out then
			table.insert(out, `... and {#list - #out} more`)
		end
		return out
	end

	local raycasts = if options.raycast == nil then canRaycast(workspace) else options.raycast
	local pathing = if options.pathfinding == nil then raycasts else options.pathfinding

	-- 1. Structure ------------------------------------------------------------------------
	local map = options.map or workspace:FindFirstChild("Map")
	local root = map or workspace
	if not map then
		add("medium", "MAP-ROOT", "No Workspace.Map. Put everything the map adds under one Map folder so it can be reviewed, moved and removed as a whole.")
	else
		local missing = {}
		for _, name in T.MapFolders do
			if not map:FindFirstChild(name) then
				table.insert(missing, name)
			end
		end
		if #missing > 0 then
			add("low", "MAP-FOLDERS", `Map has no {table.concat(missing, ", ")} folder. Sort output into Architecture, TerrainDetails, Props, Gameplay, Spawns.`)
		end
		local loose = 0
		for _, child in map:GetChildren() do
			if child:IsA("BasePart") then
				loose += 1
			end
		end
		if loose > T.LooseParts then
			add("low", "MAP-LOOSE-PARTS", `{loose} parts sit directly under Map. Group them into folders or models.`)
		end
		if map:GetAttribute("Seed") == nil then
			add("low", "MAP-SEED", "Map has no Seed attribute. Procedural maps must store their seed to be reproducible (ignore for hand-built maps).")
		end
	end

	-- 2. Parts ----------------------------------------------------------------------------
	local parts, collidable, meshes, uniqueMeshes = {}, {}, 0, {}
	local lights, neon = 0, 0
	local unanchored, tinyCollidable, precise = {}, {}, {}
	for _, instance in root:GetDescendants() do
		if instance:IsA("BasePart") and not instance:IsA("Terrain") and not inCharacter(instance) then
			table.insert(parts, instance)
			if get(instance, "CanCollide", false) then
				table.insert(collidable, instance)
			end
			if instance:IsA("MeshPart") then
				meshes += 1
				local id = get(instance, "MeshId", "")
				if id ~= "" then
					uniqueMeshes[id] = true
				end
				if get(instance, "CollisionFidelity", nil) == Enum.CollisionFidelity.PreciseConvexDecomposition then
					table.insert(precise, path(instance))
				end
			end
			if get(instance, "Material", nil) == Enum.Material.Neon then
				neon += 1
			end
			if not get(instance, "Anchored", true) and not isDynamic(instance, root) then
				table.insert(unanchored, path(instance))
			end
			local size = get(instance, "Size", nil)
			if size and get(instance, "CanCollide", false) and not instance:IsA("SpawnLocation") then
				if math.max(size.X, size.Y, size.Z) < T.TinyStuds and not hasTag(instance, "Collider") then
					table.insert(tinyCollidable, path(instance))
				end
			end
		elseif instance:IsA("Light") then
			lights += 1
		end
	end
	stats.parts = #parts
	stats.meshParts = meshes
	stats.uniqueMeshes = (function()
		local n = 0
		for _ in uniqueMeshes do
			n += 1
		end
		return n
	end)()

	if #unanchored > 0 then
		add("medium", "UNANCHORED", `{#unanchored} static parts are not anchored (they fall, drift or cost physics time). Anchor them, or tag them "Dynamic" if they are meant to move.`, sample(unanchored))
	end
	if #tinyCollidable > T.TinyCollidable then
		add("low", "TINY-COLLIDABLE", `{#tinyCollidable} parts under {T.TinyStuds} stud still collide. Turn CanCollide, CanTouch and CanQuery off for decor.`, sample(tinyCollidable))
	end
	if #precise > T.PreciseCollision then
		add("low", "PRECISE-COLLISION", `{#precise} MeshParts use Precise collision (most expensive). Use Box or Hull for decor and an invisible simple collider on key walkways.`, sample(precise))
	end

	-- 3. Spawns ---------------------------------------------------------------------------
	local spawns = {}
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") then
			table.insert(spawns, instance)
		end
	end
	stats.spawns = #spawns
	if #spawns == 0 then
		add("high", "SPAWN-NONE", "No SpawnLocation. Players spawn at the origin, often inside terrain or in the void.")
	end

	local function groundBelow(position, ignore)
		if not raycasts then
			return nil
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(position + Vector3.new(0, 200, 0), Vector3.new(0, -600, 0), params)
		return hit and hit.Position.Y or nil
	end

	local blockedSpawns, floatingSpawns, buriedSpawns = {}, {}, {}
	for _, spawn in spawns do
		local box = bounds(spawn)
		-- Anything collidable standing in the column above the pad.
		for _, other in collidable do
			if other ~= spawn and not other:IsDescendantOf(spawn) then
				local b = bounds(other)
				local overlapsXZ = b[1] < box[4] and b[4] > box[1] and b[3] < box[6] and b[6] > box[3]
				local inColumn = b[5] > box[5] + 0.05 and b[2] < box[5] + T.SpawnClearance
				if overlapsXZ and inColumn then
					table.insert(blockedSpawns, `{path(spawn)} blocked by {path(other)}`)
					break
				end
			end
		end
		if raycasts then
			local ground = groundBelow(spawn.Position, { spawn })
			if ground == nil then
				table.insert(floatingSpawns, `{path(spawn)} has nothing below it (void)`)
			else
				local gap = box[2] - ground
				if gap > T.SpawnMaxGroundGap then
					table.insert(floatingSpawns, `{path(spawn)} floats {string.format("%.1f", gap)} studs above the ground`)
				elseif gap < -T.SpawnMaxGroundGap then
					table.insert(buriedSpawns, `{path(spawn)} is {string.format("%.1f", -gap)} studs inside the ground`)
				end
			end
		end
	end
	if #blockedSpawns > 0 then
		add("high", "SPAWN-BLOCKED", `{#blockedSpawns} spawns have a solid part within {T.SpawnClearance} studs above the pad (players spawn inside geometry).`, sample(blockedSpawns))
	end
	if #floatingSpawns > 0 then
		add("high", "SPAWN-FLOATING", "Spawn pads that do not sit on ground (players fall on spawn).", sample(floatingSpawns))
	end
	if #buriedSpawns > 0 then
		add("medium", "SPAWN-BURIED", "Spawn pads sunk into terrain or floors (players spawn stuck or half hidden).", sample(buriedSpawns))
	end
	if not raycasts and #spawns > 0 then
		table.insert(report.skipped, "spawn ground check (needs raycasts: run validate_map.luau in Studio)")
	end

	-- 4. Doors and goals ------------------------------------------------------------------
	local narrow, goals = {}, {}
	for _, instance in root:GetDescendants() do
		if instance:IsA("BasePart") then
			if hasTag(instance, "Door") then
				local size = instance.Size
				local width, height = math.max(size.X, size.Z), size.Y
				if width < T.DoorMinWidth or height < T.DoorMinHeight then
					table.insert(narrow, `{path(instance)} opening {string.format("%.1f", width)} x {string.format("%.1f", height)}`)
				end
			end
			if hasTag(instance, "Goal") then
				table.insert(goals, instance)
			end
		end
	end
	stats.goals = #goals
	if #narrow > 0 then
		add("medium", "DOOR-TOO-SMALL", `{#narrow} openings are smaller than {T.DoorMinWidth} x {T.DoorMinHeight} studs (avatars and NPCs get stuck).`, sample(narrow))
	end
	if #goals == 0 then
		add("low", "GOALS-UNTAGGED", `No part is tagged "Goal", so reachability from the spawns cannot be checked. Tag objectives, exits, shops and bosses.`)
	end

	if pathing and #goals > 0 and #spawns > 0 then
		local pathfinding = game:GetService("PathfindingService")
		local unreachable = {}
		local checked = 0
		for _, spawn in spawns do
			for index, goal in goals do
				if index > T.MaxGoals then
					break
				end
				local ok, status = pcall(function()
					local route = pathfinding:CreatePath(options.agent or T.Agent)
					route:ComputeAsync(spawn.Position + Vector3.new(0, 3, 0), goal.Position)
					return route.Status
				end)
				checked += 1
				if not ok or status ~= Enum.PathStatus.Success then
					table.insert(unreachable, `{path(spawn)} -> {path(goal)} ({if ok then tostring(status) else "error"})`)
				end
			end
		end
		stats.pathsChecked = checked
		if #unreachable > 0 then
			add("high", "GOAL-UNREACHABLE", `{#unreachable} spawn -> goal routes have no path for the agent (radius {(options.agent or T.Agent).AgentRadius}, height {(options.agent or T.Agent).AgentHeight}). Check doors, gaps and jump heights.`, sample(unreachable))
		end
	elseif #goals > 0 and #spawns > 0 then
		table.insert(report.skipped, "pathfinding spawn -> goal (needs Studio: run validate_map.luau there)")
	end

	-- 5. Floating and buried props --------------------------------------------------------
	if raycasts then
		local floating, buried = {}, {}
		local propsFolder = map and map:FindFirstChild("Props")
		local checked = 0
		if propsFolder then
			for _, instance in propsFolder:GetDescendants() do
				if checked >= T.RaycastProps then
					break
				end
				if instance:IsA("BasePart") and get(instance, "Anchored", false) then
					checked += 1
					local box = bounds(instance)
					local ignore = { instance }
					local model = instance:FindFirstAncestorWhichIsA("Model")
					if model and model ~= map then
						ignore = { model }
					end
					local ground = groundBelow(instance.Position, ignore)
					if ground then
						local gap = box[2] - ground
						if gap > T.PropMaxFloat then
							table.insert(floating, `{path(instance)} {string.format("%.1f", gap)} studs above the ground`)
						elseif gap < -T.PropMaxBuried then
							table.insert(buried, `{path(instance)} {string.format("%.1f", -gap)} studs inside the ground`)
						end
					end
				end
			end
		end
		stats.propsRaycast = checked
		if #floating > 0 then
			add("medium", "PROP-FLOATING", `{#floating} props hover above the ground below them. Props stacked on other props are expected: confirm before moving.`, sample(floating))
		end
		if #buried > 0 then
			add("low", "PROP-BURIED", `{#buried} props are buried deeper than {T.PropMaxBuried} studs.`, sample(buried))
		end
	else
		table.insert(report.skipped, "floating / buried props (needs raycasts: run validate_map.luau in Studio)")
	end

	-- 6. Coplanar faces (z-fighting) ------------------------------------------------------
	-- Two axis-aligned parts whose top (or bottom, front...) faces lie in the same plane and
	-- overlap, with different colours or materials, flicker against each other.
	if #parts <= T.CoplanarMaxParts then
		local CELL = 32
		local items = {}
		for _, part in parts do
			if
				part.Transparency < 1
				and not part:IsA("Terrain")
				and not part:IsA("SpawnLocation")
				and axisAligned(part)
				and not hasTag(part, "Decal")
			then
				table.insert(items, { part = part, box = bounds(part) })
			end
		end
		local grid = {}
		for index, item in items do
			local b = item.box
			for cx = math.floor(b[1] / CELL), math.floor(b[4] / CELL) do
				for cz = math.floor(b[3] / CELL), math.floor(b[6] / CELL) do
					local key = cx * 100003 + cz
					grid[key] = grid[key] or {}
					table.insert(grid[key], index)
				end
			end
		end
		local seen, found, foundMore = {}, {}, 0
		local tol, minOverlap = T.CoplanarTolerance, T.CoplanarMinOverlap
		for _, cell in grid do
			for i = 1, #cell do
				for j = i + 1, #cell do
					local a, b = cell[i], cell[j]
					local pairKey = a * 1000003 + b
					if not seen[pairKey] then
						seen[pairKey] = true
						local A, B = items[a], items[b]
						local ba, bb = A.box, B.box
						local differs = get(A.part, "Color", nil) ~= get(B.part, "Color", nil)
							or get(A.part, "Material", nil) ~= get(B.part, "Material", nil)
						if differs then
							for axis = 0, 2 do
								-- the two other axes must overlap by more than minOverlap
								local o1, o2 = (axis + 1) % 3, (axis + 2) % 3
								local ov1 = math.min(ba[o1 + 4], bb[o1 + 4]) - math.max(ba[o1 + 1], bb[o1 + 1])
								local ov2 = math.min(ba[o2 + 4], bb[o2 + 4]) - math.max(ba[o2 + 1], bb[o2 + 1])
								if ov1 > minOverlap and ov2 > minOverlap then
									local sameMax = math.abs(ba[axis + 4] - bb[axis + 4]) < tol
									local sameMin = math.abs(ba[axis + 1] - bb[axis + 1]) < tol
									-- the faces must also be inside each other's depth range, or
									-- these are two separate things that merely line up
									local depthOverlap = math.min(ba[axis + 4], bb[axis + 4]) - math.max(ba[axis + 1], bb[axis + 1])
									if (sameMax or sameMin) and depthOverlap > tol then
										if #found < T.CoplanarExamples then
											table.insert(found, `{path(A.part)} / {path(B.part)}`)
										else
											foundMore += 1
										end
										break
									end
								end
							end
						end
					end
				end
			end
		end
		local total = #found + foundMore
		stats.coplanarPairs = total
		if total > 0 then
			add("medium", "Z-FIGHTING", `{total} pairs of overlapping parts share a face plane with different colour or material (flickering surfaces). Inset one by 0.05-0.1 stud, or shrink/merge the overlap.`, found)
		end
	else
		table.insert(report.skipped, `z-fighting check (map has {#parts} parts, over {T.CoplanarMaxParts})`)
	end

	-- 7. Lighting and streaming -----------------------------------------------------------
	local effectCounts = {}
	for _, child in lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") then
			effectCounts[child.ClassName] = (effectCounts[child.ClassName] or 0) + 1
		end
	end
	for className, count in effectCounts do
		if count > 1 then
			add("low", "STACKED-POSTFX", `{count} {className} objects in Lighting stack on top of each other (often template + custom). Keep one.`)
		end
	end
	local atmosphere = lighting:FindFirstChildOfClass("Atmosphere")
	local fogEnd = get(lighting, "FogEnd", 100000)
	if atmosphere and fogEnd < 100000 then
		add("low", "FOG-IGNORED", `Atmosphere is present, so Lighting.FogEnd ({fogEnd}) is ignored. Use Atmosphere Density/Haze for depth, not both.`)
	end
	if neon >= T.NeonWithoutLight and lights == 0 then
		add("low", "NEON-NO-LIGHT", `{neon} Neon parts and no Point/Surface/Spot light in the map. Neon does not light its surroundings: add real lights beside it.`)
	end
	local style = get(lighting, "LightingStyle", nil)
	stats.lightingStyle = if style then tostring(style) else "unreadable"
	if get(workspace, "StreamingEnabled", true) == false and #parts > T.NoStreamingParts then
		add("medium", "NO-STREAMING", `StreamingEnabled is off with {#parts} parts in the map. Turn it on (Improved, PauseOutsideLoadedArea) and keep modules to ~64 studs.`)
	end

	local order = { high = 1, medium = 2, low = 3 }
	table.sort(report.findings, function(a, b)
		if order[a.severity] ~= order[b.severity] then
			return order[a.severity] < order[b.severity]
		end
		return a.rule < b.rule
	end)
	return report
end

function Validator.format(report)
	local lines = { "== Map validation ==" }
	local keys = {}
	for key in report.stats do
		table.insert(keys, key)
	end
	table.sort(keys)
	local stats = {}
	for _, key in keys do
		table.insert(stats, `{key}={tostring(report.stats[key])}`)
	end
	table.insert(lines, "stats: " .. table.concat(stats, ", "))
	local totals = { high = 0, medium = 0, low = 0 }
	for _, finding in report.findings do
		totals[finding.severity] += 1
		table.insert(lines, `{string.upper(finding.severity)} {finding.rule}: {finding.message}`)
		for _, example in finding.examples do
			table.insert(lines, `    - {example}`)
		end
	end
	for _, note in report.skipped do
		table.insert(lines, `SKIPPED {note}`)
	end
	table.insert(lines, `{totals.high} high, {totals.medium} medium, {totals.low} low, {#report.skipped} skipped`)
	return table.concat(lines, "\n"), totals
end

if MAP_RETURN then
	return Validator
end
local text = Validator.format(Validator.run(game))
print(text)
return text
