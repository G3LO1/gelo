-- Test slices for slice_check.luau: Slices.good() is a small house on a 4-stud kit (ground, floors,
-- walls, a door frame, roof, interior, a route from outside in through the door, four eye-height
-- viewpoints, a landmark); Slices.broken(name) breaks one thing.

local roblox = require("@lune/roblox")
local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

local function new(className, props, parent)
	local instance = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function part(parent, name, size, position, extra)
	local p = new("Part", { Name = name, Anchored = true, Size = size, CFrame = CFrame.new(position) }, parent)
	for key, value in extra or {} do
		p[key] = value
	end
	return p
end

local function kit(p, module)
	p:AddTag("Kit")
	p:SetAttribute("Module", module)
	return p
end

local function marker(parent, tag, name, size, position, attributes)
	local p = part(parent, name, size, position, { CanCollide = false, Transparency = 1 })
	p:AddTag(tag)
	for key, value in attributes or {} do
		p:SetAttribute(key, value)
	end
	return p
end

local Slices = {}

function Slices.good()
	local game = Instance.new("DataModel")
	local ws = game:GetService("Workspace")
	local map = new("Model", { Name = "Map" }, ws)
	local slice = new("Model", { Name = "Slice" }, map)
	slice:SetAttribute("Grid", 4)
	part(slice, "Ground", Vector3.new(48, 1, 48), Vector3.new(8, -0.5, 8))
	for i, c in { { 4, 4 }, { 12, 4 }, { 4, 12 }, { 12, 12 } } do
		kit(part(slice, `Floor{i}`, Vector3.new(8, 1, 8), Vector3.new(c[1], 0.5, c[2])), "Floor8")
		kit(part(slice, `Roof{i}`, Vector3.new(8, 1, 8), Vector3.new(c[1], 13.5, c[2])), "Roof8")
	end
	kit(part(slice, "WallN1", Vector3.new(8, 12, 1), Vector3.new(4, 7, 16)), "Wall8")
	kit(part(slice, "WallN2", Vector3.new(8, 12, 1), Vector3.new(12, 7, 16)), "Wall8")
	kit(part(slice, "WallS1", Vector3.new(8, 12, 1), Vector3.new(4, 7, 0)), "Wall8")
	for i, z in { 4, 12 } do
		local west = kit(part(slice, `WallW{i}`, Vector3.new(8, 12, 1), Vector3.new(0, 7, z)), "Wall8")
		west.CFrame = CFrame.new(0, 7, z) * CFrame.Angles(0, math.rad(90), 0)
		local east = kit(part(slice, `WallE{i}`, Vector3.new(8, 12, 1), Vector3.new(16, 7, z)), "Wall8")
		east.CFrame = CFrame.new(16, 7, z) * CFrame.Angles(0, math.rad(90), 0)
	end
	-- door frame module: two jambs and a lintel around a 4 x 8 opening, an invisible bounds part as PrimaryPart
	local frame = new("Model", { Name = "DoorFrame" }, slice)
	kit(frame, "DoorFrame8")
	frame.PrimaryPart = part(frame, "Bounds", Vector3.new(8, 12, 1), Vector3.new(12, 7, 0), { CanCollide = false, Transparency = 1 })
	part(frame, "JambL", Vector3.new(2, 12, 1), Vector3.new(9, 7, 0))
	part(frame, "JambR", Vector3.new(2, 12, 1), Vector3.new(15, 7, 0))
	part(frame, "Lintel", Vector3.new(4, 4, 1), Vector3.new(12, 11, 0))
	marker(slice, "Doorway", "FrontDoor", Vector3.new(4, 8, 1), Vector3.new(12, 5, 0))
	marker(slice, "Interior", "Hall", Vector3.new(15, 12, 15), Vector3.new(8, 7, 8))
	for order, position in { Vector3.new(12, 0.1, -8), Vector3.new(12, 0.1, -2), Vector3.new(12, 1.1, 3), Vector3.new(8, 1.1, 10) } do
		marker(slice, "Route", `Route{order}`, Vector3.new(1, 0.2, 1), position, { Order = order })
	end
	local views = {
		Entrance = { Vector3.new(12, 4.8, -10), Vector3.new(12, 4.8, 0) },
		Route = { Vector3.new(14, 4.8, -3), Vector3.new(12, 5, 4) },
		Interior = { Vector3.new(12, 5.8, 4), Vector3.new(4, 5, 12) },
		Scale = { Vector3.new(3, 5.8, 3), Vector3.new(12, 3, 3) },
	}
	for name, v in views do
		local p = marker(slice, "Viewpoint", `View{name}`, Vector3.new(1, 1, 1), v[1], { View = name })
		p.CFrame = CFrame.lookAt(v[1], v[2])
	end
	part(slice, "Lantern", Vector3.new(1, 3, 1), Vector3.new(14, 2.5, 14)):AddTag("Landmark")
	return game, slice
end

local BREAK = {
	lowdoor = function(s)
		s.FrontDoor.Size = Vector3.new(4, 6, 1)
	end,
	blocked = function(s)
		part(s, "Crate", Vector3.new(3, 3, 3), Vector3.new(10, 2.5, 6.5))
	end,
	nofloor = function(s)
		s.Ground:Destroy()
	end,
	step = function(s)
		for i = 1, 4 do
			s[`Floor{i}`].CFrame += Vector3.new(0, 3, 0)
		end
		s.Route3.CFrame += Vector3.new(0, 3, 0) -- the markers inside stand on the raised floor
		s.Route4.CFrame += Vector3.new(0, 3, 0)
	end,
	noview = function(s)
		s.ViewScale:Destroy()
	end,
	eye = function(s)
		s.ViewInterior.CFrame = CFrame.lookAt(Vector3.new(12, 9, 4), Vector3.new(4, 5, 12))
	end,
	offgrid = function(s)
		s.Roof2.CFrame += Vector3.new(1, 0, 0)
	end,
	size = function(s)
		s.WallN2.Size = Vector3.new(8, 11, 1)
	end,
	overlap = function(s)
		kit(part(s, "Floor5", Vector3.new(8, 1, 8), Vector3.new(8, 0.5, 4)), "Floor8")
	end,
	turned = function(s)
		s.WallS1.CFrame = CFrame.new(4, 7, 0) * CFrame.Angles(0, math.rad(45), 0)
	end,
	lowceiling = function(s)
		s.Hall.Size = Vector3.new(15, 8, 15)
	end,
	nodoor = function(s)
		s.Route2.CFrame = CFrame.new(4, 0.1, -2)
		s.Route3.CFrame = CFrame.new(4, 1.1, 3)
	end,
}
Slices.cases = {}
for name in BREAK do
	table.insert(Slices.cases, name)
end
table.sort(Slices.cases)

function Slices.broken(name)
	local game, slice = Slices.good()
	BREAK[name](slice)
	return game, slice
end

return Slices
