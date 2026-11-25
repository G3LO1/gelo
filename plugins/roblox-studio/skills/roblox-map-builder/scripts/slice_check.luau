-- Slice acceptance: check ONE complete piece of the map (outside, entrance, route, interior) at
-- player scale before its kit modules are duplicated across the map. Runs in Studio (Command Bar or
-- the Studio MCP execute_luau tool, on Workspace.Map.Slice) and in Lune on a place or model file:
--
--   lune run slice_check.luau <place.rbxl | slice.rbxm> [--slice Workspace/Map/Slice] [--scene walk.json]
--
-- What the slice must carry (CollectionService tags, set them in Studio's Tag Editor or by script):
--   Kit        every kit piece (Part, or Model with a PrimaryPart) with attribute Module = "Wall4" ...
--   Doorway    an invisible, non-colliding box filling each door opening
--   Interior   an invisible box filling the inside (its height is the room's clear height)
--   Route      invisible markers on the floor with attribute Order = 1, 2, 3 ... (outside -> in)
--   Viewpoint  invisible parts at eye height looking where a player would look, attribute
--              View = "Entrance" | "Route" | "Interior" | "Scale"
--   Landmark   optional: the thing players steer by
-- Slice attributes (optional): Grid (studs, default 4), AvatarHeight (6), AvatarWidth (2.5),
-- MinCeiling (9), MaxStep (2.2).
--
-- Checks: doors fit the avatar; the route has floor under it, no blocking part, no step a player
-- can't climb, and goes in through a doorway; the interior is tall enough and on the route; the four
-- player-height viewpoints exist at eye height; kit pieces sit on the grid, turn in 90-degree steps,
-- and every copy of a module has the same size (so it can be duplicated); no piece runs through
-- another (more than 10% of the smaller one's volume shared; corner joints are fine).
-- --scene writes a scene for roblox-launch-kit's ShotDirector that walks the four viewpoints at
-- player eye height: use the SAME scene file for every variant you compare.

local SliceCheck = {}

local VIEWS = { "Entrance", "Route", "Interior", "Scale" }
local MARKERS = { Doorway = true, Interior = true, Route = true, Viewpoint = true }

local function attr(instance, name, default)
	local value = instance:GetAttribute(name)
	return if value == nil then default else value
end

local function tagged(root, tag)
	local out = {}
	for _, d in root:GetDescendants() do
		if d:HasTag(tag) then
			table.insert(out, d)
		end
	end
	return out
end

local function isMarker(part)
	for tag in MARKERS do
		if part:HasTag(tag) then
			return true
		end
	end
	return false
end

-- is a world point inside a part's box (shrunk by `inset` on every side)?
local function inside(part, point, inset)
	local p = part.CFrame:PointToObjectSpace(point)
	local h = part.Size / 2
	local e = inset or 0
	return math.abs(p.X) < h.X - e and math.abs(p.Y) < h.Y - e and math.abs(p.Z) < h.Z - e
end

-- world-space axis-aligned bounds of a part
local function bounds(part)
	local cf, h = part.CFrame, part.Size / 2
	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = -low
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local corner = cf:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z))
				low = Vector3.new(math.min(low.X, corner.X), math.min(low.Y, corner.Y), math.min(low.Z, corner.Z))
				high = Vector3.new(math.max(high.X, corner.X), math.max(high.Y, corner.Y), math.max(high.Z, corner.Z))
			end
		end
	end
	return low, high
end

-- the highest collidable surface at or below `point` (within `reach` studs), or nil
local function floorBelow(solids, point, reach)
	local best = nil
	for _, part in solids do
		local p = part.CFrame:PointToObjectSpace(point)
		local h = part.Size / 2
		if math.abs(p.X) <= h.X + 0.01 and math.abs(p.Z) <= h.Z + 0.01 then
			local _, high = bounds(part)
			local top = high.Y
			if top <= point.Y + 0.05 and top >= point.Y - reach and (best == nil or top > best) then
				best = top
			end
		end
	end
	return best
end

local function round(v, step)
	return math.floor(v / step + 0.5) * step
end

local function fmt(v)
	return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end

local function n(v)
	return string.format("%g", math.floor(v * 10 + 0.5) / 10)
end

function SliceCheck.run(slice)
	local report = { lines = {}, scene = nil }
	local function add(level, message)
		table.insert(report.lines, { level, message })
	end
	local grid = attr(slice, "Grid", 4)
	local avatarH = attr(slice, "AvatarHeight", 6)
	local avatarW = attr(slice, "AvatarWidth", 2.5)
	local minCeiling = attr(slice, "MinCeiling", 9)
	local maxStep = attr(slice, "MaxStep", 2.2)

	local solids = {}
	for _, d in slice:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide and not isMarker(d) then
			table.insert(solids, d)
		end
	end

	-- doors
	local doors = tagged(slice, "Doorway")
	if #doors == 0 then
		add("FAIL", "no Doorway: tag a box filling each door opening")
	end
	for _, door in doors do
		local width = math.max(door.Size.X, door.Size.Z) -- the other horizontal side is the wall's thickness
		if door.Size.Y < avatarH + 1 then
			add("FAIL", `door {door.Name}: {n(door.Size.Y)} studs high, the avatar needs {avatarH + 1} ({avatarH} + head room)`)
		elseif width < avatarW + 1.5 then
			add("FAIL", `door {door.Name}: {n(width)} studs wide, the avatar needs {avatarW + 1.5}`)
		else
			add("PASS", `door {door.Name}: {n(width)} x {n(door.Size.Y)} studs fits the avatar`)
		end
		for _, solid in solids do
			if inside(solid, door.CFrame.Position, 0.05) then
				add("FAIL", `door {door.Name} is blocked by {solid.Name}`)
			end
		end
	end

	-- route
	local route = tagged(slice, "Route")
	table.sort(route, function(a, b)
		return attr(a, "Order", 0) < attr(b, "Order", 0)
	end)
	local throughDoor = false
	if #route < 2 then
		add("FAIL", "the route needs at least 2 Route markers (Order 1, 2 ...) from outside to inside")
	else
		local blocked, gaps, steps = {}, {}, {}
		local lastFloor = nil
		for i = 1, #route - 1 do
			local a, b = route[i].CFrame.Position, route[i + 1].CFrame.Position
			local samples = math.max(1, math.ceil((b - a).Magnitude / 0.5))
			for s = 0, samples do
				local point = a:Lerp(b, s / samples)
				local floor = floorBelow(solids, point + Vector3.new(0, 1, 0), 3)
				if floor == nil then
					gaps[#gaps + 1] = `{fmt(point)} (between markers {i} and {i + 1})`
				else
					if lastFloor and floor - lastFloor > maxStep then
						steps[#steps + 1] = `{n(floor - lastFloor)} studs up near {fmt(point)}`
					end
					lastFloor = floor
					local feet = Vector3.new(point.X, floor, point.Z)
					for _, solid in solids do
						-- body probes start above a climbable step; higher steps are the step check's job
						for _, height in { maxStep + 0.2, avatarH / 2, avatarH - 0.3 } do
							for _, side in { -avatarW / 2, 0, avatarW / 2 } do
								local probe = feet + Vector3.new(side, height, 0)
								local probe2 = feet + Vector3.new(0, height, side)
								if (inside(solid, probe, 0.02) or inside(solid, probe2, 0.02)) and not blocked[solid] then
									blocked[solid] = `{solid.Name} at {fmt(point)} (between markers {i} and {i + 1})`
								end
							end
						end
					end
				end
				for _, door in doors do
					if inside(door, point + Vector3.new(0, 1, 0), 0) then
						throughDoor = true
					end
				end
			end
		end
		local blockers = {}
		for _, message in blocked do
			table.insert(blockers, message)
		end
		table.sort(blockers)
		for _, message in blockers do
			add("FAIL", `route blocked by {message}`)
		end
		if #gaps > 0 then
			add("FAIL", `no floor under the route at {#gaps} point(s), first {gaps[1]}`)
		end
		for _, message in steps do
			add("FAIL", `step of {message}: higher than MaxStep {maxStep} (stairs or a ramp)`)
		end
		if #doors > 0 and not throughDoor then
			add("FAIL", "the route never goes through a doorway: walk it from outside, in through the door")
		end
		if #blockers == 0 and #gaps == 0 and #steps == 0 and (throughDoor or #doors == 0) then
			add("PASS", `route: {#route} markers walkable at avatar size, in through the door`)
		end
	end

	-- interior
	local interiors = tagged(slice, "Interior")
	if #interiors == 0 then
		add("FAIL", "no Interior: tag a box filling the inside (first-person players see it as much as the outside)")
	end
	for _, room in interiors do
		local onRoute = false
		for _, marker in route do
			if inside(room, marker.CFrame.Position + Vector3.new(0, 1, 0), 0) then
				onRoute = true
			end
		end
		if room.Size.Y < minCeiling then
			add("FAIL", `interior {room.Name}: {n(room.Size.Y)} studs to the ceiling, MinCeiling is {minCeiling}`)
		else
			add("PASS", `interior {room.Name}: {n(room.Size.Y)} studs clear height`)
		end
		if not onRoute then
			add("FAIL", `interior {room.Name}: no Route marker inside it`)
		end
	end

	-- player-height viewpoints
	local views = {}
	for _, view in tagged(slice, "Viewpoint") do
		views[attr(view, "View", view.Name)] = view
	end
	local keys = {}
	for index, name in VIEWS do
		local view = views[name]
		if not view then
			add("FAIL", `no Viewpoint with View = "{name}" (player-height views: Entrance, Route, Interior, Scale)`)
			continue
		end
		local floor = floorBelow(solids, view.CFrame.Position, 12)
		local eye = if floor then view.CFrame.Position.Y - floor else nil
		if eye == nil then
			add("FAIL", `viewpoint {name}: no floor under it`)
		elseif eye < avatarH * 0.65 or eye > avatarH * 0.95 then
			add("FAIL", `viewpoint {name}: {n(eye)} studs above the floor; eye height for a {avatarH}-stud avatar is about {n(avatarH * 0.8)}`)
		else
			add("PASS", `viewpoint {name} at eye height ({n(eye)} studs)`)
		end
		local look = view.CFrame.Position + view.CFrame.LookVector * 12
		local function v3(v)
			return { math.floor(v.X * 1000 + 0.5) / 1000, math.floor(v.Y * 1000 + 0.5) / 1000, math.floor(v.Z * 1000 + 0.5) / 1000 }
		end
		table.insert(keys, {
			at = (index - 1) * 2.5,
			position = v3(view.CFrame.Position),
			lookAt = v3(look),
			fov = 70,
			ease = "Sine",
		})
	end
	if #tagged(slice, "Landmark") == 0 then
		add("WARN", "no Landmark: one thing players steer by, visible from the entrance")
	end

	-- kit modules
	local kit = tagged(slice, "Kit")
	local sizes, pieces = {}, {}
	for _, piece in kit do
		local part = if piece:IsA("Model") then piece.PrimaryPart else piece
		local module = attr(piece, "Module", nil)
		if not part then
			add("FAIL", `kit piece {piece.Name}: a Model needs a PrimaryPart`)
			continue
		end
		if not module then
			add("FAIL", `kit piece {piece.Name}: no Module attribute (which kit module it is)`)
			continue
		end
		table.insert(pieces, part)
		local cf = part.CFrame
		local _, yaw = cf:ToEulerAnglesYXZ()
		local degrees = math.deg(yaw)
		local pivot = part.CFrame.Position - part.CFrame:VectorToWorldSpace(Vector3.new(0, part.Size.Y / 2, 0)) -- bottom center
		if math.abs(degrees - round(degrees, 90)) > 0.5 then
			add("FAIL", `kit piece {piece.Name} ({module}): turned {n(degrees)} degrees; kit pieces turn in 90-degree steps`)
		end
		local offX, offZ = math.abs(pivot.X - round(pivot.X, grid / 2)), math.abs(pivot.Z - round(pivot.Z, grid / 2))
		if offX > 0.01 or offZ > 0.01 then
			add("FAIL", `kit piece {piece.Name} ({module}): bottom center {fmt(pivot)} is off the {grid}-stud grid`)
		end
		local size = part.Size
		local key = string.format("%.2f x %.2f x %.2f", size.X, size.Y, size.Z)
		sizes[module] = sizes[module] or {}
		sizes[module][key] = (sizes[module][key] or 0) + 1
	end
	for module, variants in sizes do
		local list = {}
		for key, count in variants do
			table.insert(list, `{key} ({count})`)
		end
		if #list > 1 then
			table.sort(list)
			add("FAIL", `module {module} has {#list} different sizes: {table.concat(list, ", ")}; every copy of a module must be the same piece`)
		end
	end
	for i = 1, #pieces do
		for j = i + 1, #pieces do
			local aLow, aHigh = bounds(pieces[i])
			local bLow, bHigh = bounds(pieces[j])
			local ox = math.min(aHigh.X, bHigh.X) - math.max(aLow.X, bLow.X)
			local oy = math.min(aHigh.Y, bHigh.Y) - math.max(aLow.Y, bLow.Y)
			local oz = math.min(aHigh.Z, bHigh.Z) - math.max(aLow.Z, bLow.Z)
			-- corner joints share a sliver; a piece through another shares a real part of its volume
			local smaller = math.min(pieces[i].Size.X * pieces[i].Size.Y * pieces[i].Size.Z, pieces[j].Size.X * pieces[j].Size.Y * pieces[j].Size.Z)
			if ox > 0.1 and oy > 0.1 and oz > 0.1 and ox * oy * oz > 0.1 * smaller then
				add("FAIL", `kit pieces {pieces[i].Name} and {pieces[j].Name} overlap ({n(ox)} x {n(oy)} x {n(oz)} studs): a piece through another, or z-fighting`)
			end
		end
	end
	if #kit > 0 then
		local count = 0
		for _ in sizes do
			count += 1
		end
		add("INFO", `{#kit} kit pieces, {count} module(s), grid {grid}`)
	else
		add("FAIL", "no Kit pieces: tag the slice's modular pieces Kit with a Module attribute")
	end

	if #keys > 0 then
		report.scene = {
			name = `{slice.Name}Walk`,
			length = math.max(2.5, (#keys - 1) * 2.5),
			ready = { preload = {}, streamAround = true, timeout = 10, rehearse = true },
			camera = keys,
			actors = {},
			events = {},
			shots = {},
		}
		for index, name in VIEWS do
			if views[name] then
				table.insert(report.scene.shots, { at = (index - 1) * 2.5, name = name, use = { "test" } })
			end
		end
	end
	return report
end

function SliceCheck.format(report)
	local out, fails = {}, 0
	for _, line in report.lines do
		table.insert(out, `{line[1]}  {line[2]}`)
		if line[1] == "FAIL" then
			fails += 1
		end
	end
	table.insert(out, `{fails} failed`)
	return table.concat(out, "\n"), fails
end

-- Lune: `lune run slice_check.luau <file> [--slice path] [--scene out.json]`
-- Studio: run the file as is; it checks Workspace.Map.Slice and prints the report.
if SLICE_RETURN then
	return SliceCheck
end
if typeof(game) == "Instance" then -- Roblox Studio
	local map = workspace:FindFirstChild("Map")
	local slice = map and map:FindFirstChild("Slice")
	assert(slice, "no Workspace.Map.Slice")
	print((SliceCheck.format(SliceCheck.run(slice))))
	return SliceCheck
end

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
Vector3 = roblox.Vector3 -- the checks above use Roblox's datatypes as globals, like in Studio
local args = process.args
if not args[1] then
	print("usage: lune run slice_check.luau <place.rbxl|slice.rbxm> [--slice Workspace/Map/Slice] [--scene out.json]")
	process.exit(2)
end
local options = {}
for i = 2, #args, 2 do
	options[string.gsub(args[i], "^%-%-", "")] = args[i + 1]
end
local contents = fs.readFile(args[1])
local root
if string.match(args[1], "%.rbxlx?$") then
	root = roblox.deserializePlace(contents)
else
	root = roblox.Instance.new("DataModel")
	local ws = root:GetService("Workspace")
	for _, instance in roblox.deserializeModel(contents) do
		instance.Parent = ws
	end
end
local slice = root
for part in string.gmatch(options.slice or "Workspace/Map/Slice", "[^/]+") do
	slice = slice and (if slice == root and part == "Workspace" then root:GetService("Workspace") else slice:FindFirstChild(part))
end
if not slice then
	print(`no slice at {options.slice or "Workspace/Map/Slice"}`)
	process.exit(2)
end
local report = SliceCheck.run(slice)
local text, fails = SliceCheck.format(report)
print(text)
if options.scene and report.scene then
	fs.writeFile(options.scene, serde.encode("json", report.scene, true))
	print(`wrote {options.scene}: player-height walkthrough for roblox-launch-kit's ShotDirector`)
end
process.exit(if fails == 0 then 0 else 1)
