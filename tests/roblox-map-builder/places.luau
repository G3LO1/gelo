-- Test maps for validate_map.luau: Maps.clean() is a tidy small map that must produce no
-- findings, Maps.bad() has one of every problem the validator looks for.

local roblox = require("@lune/roblox")

local Instance, Enum, Vector3, Color3, CFrame = roblox.Instance, roblox.Enum, roblox.Vector3, roblox.Color3, roblox.CFrame

-- Lune keeps Position and CFrame apart (Position does not move the CFrame, and only the
-- CFrame is saved), so positions are always written as a CFrame.
local function apply(instance, props)
	for key, value in props do
		if key == "Position" then
			instance.CFrame = CFrame.new(value)
		else
			instance[key] = value
		end
	end
end

local function new(className, props, parent)
	local instance = Instance.new(className)
	apply(instance, props)
	instance.Parent = parent
	return instance
end

local function configured(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = Vector3.new(8, 1, 8)
	apply(p, props)
	p.Parent = parent
	return p
end

local function folders(map, names)
	local made = {}
	for _, name in names do
		made[name] = new("Folder", { Name = name }, map)
	end
	return made
end

local ALL = { "Architecture", "TerrainDetails", "Props", "Gameplay", "Spawns" }
local Maps = {}

function Maps.clean()
	local place = Instance.new("DataModel")
	local ws = place:GetService("Workspace")
	ws.StreamingEnabled = true
	local map = new("Folder", { Name = "Map" }, ws)
	map:SetAttribute("Seed", 7)
	local f = folders(map, ALL)

	configured(f.Architecture, { Name = "Floor", Size = Vector3.new(100, 1, 100), Position = Vector3.new(0, 0, 0) })
	new("SpawnLocation", { Anchored = true, Size = Vector3.new(12, 1, 12), Position = Vector3.new(0, 1, 0) }, f.Spawns)
	local goal = configured(f.Gameplay, { Name = "Exit", Position = Vector3.new(40, 1, 0), Transparency = 1, CanCollide = false })
	goal:AddTag("Goal")
	local door = configured(f.Architecture, { Name = "DoorOpening", Size = Vector3.new(6, 9, 1), Position = Vector3.new(20, 5, 0), Transparency = 1, CanCollide = false })
	door:AddTag("Door")
	for i = 1, 5 do
		configured(f.Props, { Name = `Rock{i}`, Size = Vector3.new(2, 2, 2), Position = Vector3.new(-10 - i * 6, 1.5, 10) })
	end
	local lamp = configured(f.Props, { Name = "Lamp", Size = Vector3.new(1, 6, 1), Position = Vector3.new(10, 4, 10) })
	new("PointLight", { Range = 14 }, lamp)
	configured(f.Props, { Name = "GlowStrip", Size = Vector3.new(6, 0.4, 0.4), Position = Vector3.new(10, 8, 10), Material = Enum.Material.Neon })

	local lighting = place:GetService("Lighting")
	new("BloomEffect", {}, lighting)
	new("Atmosphere", {}, lighting)
	return place
end

-- Expected rules (with the thresholds from Maps.badThresholds applied):
-- high SPAWN-BLOCKED; medium DOOR-TOO-SMALL NO-STREAMING UNANCHORED Z-FIGHTING;
-- low FOG-IGNORED GOALS-UNTAGGED MAP-FOLDERS MAP-SEED NEON-NO-LIGHT STACKED-POSTFX TINY-COLLIDABLE
Maps.badThresholds = { NoStreamingParts = 10, TinyCollidable = 2 }

function Maps.bad()
	local place = Instance.new("DataModel")
	local ws = place:GetService("Workspace")
	ws.StreamingEnabled = false
	local map = new("Folder", { Name = "Map" }, ws)
	local f = folders(map, { "Architecture", "Props", "Spawns" }) -- no TerrainDetails / Gameplay, no Seed

	-- z-fighting: a rug whose top face is the slab's top face, different colour
	configured(f.Architecture, { Name = "Slab", Size = Vector3.new(20, 1, 20), Position = Vector3.new(0, 0, 0), Color = Color3.fromRGB(200, 40, 40) })
	configured(f.Architecture, { Name = "Rug", Size = Vector3.new(10, 0.5, 10), Position = Vector3.new(0, 0.25, 0), Color = Color3.fromRGB(40, 40, 200) })

	-- spawn with a ceiling 3 studs above the pad
	new("SpawnLocation", { Anchored = true, Size = Vector3.new(12, 1, 12), Position = Vector3.new(200, 1, 0) }, f.Spawns)
	configured(f.Architecture, { Name = "LowCeiling", Size = Vector3.new(20, 1, 20), Position = Vector3.new(200, 4, 0) })

	-- door opening 3 x 6 (too small)
	local door = configured(f.Architecture, { Name = "DoorOpening", Size = Vector3.new(3, 6, 1), Position = Vector3.new(-50, 4, 0), Transparency = 1, CanCollide = false })
	door:AddTag("Door")

	-- a static part that is not anchored
	configured(f.Props, { Name = "Crate", Size = Vector3.new(3, 3, 3), Position = Vector3.new(300, 5, 0), Anchored = false })

	-- tiny collidable decor
	for i = 1, 3 do
		configured(f.Props, { Name = `Pebble{i}`, Size = Vector3.new(0.5, 0.5, 0.5), Position = Vector3.new(400 + i * 5, 20, 0) })
	end

	-- Neon, no lights
	for i = 1, 6 do
		configured(f.Props, { Name = `NeonSign{i}`, Size = Vector3.new(4, 1, 1), Position = Vector3.new(500 + i * 8, 30, 0), Material = Enum.Material.Neon })
	end

	local lighting = place:GetService("Lighting")
	new("BloomEffect", {}, lighting)
	new("BloomEffect", {}, lighting)
	new("Atmosphere", {}, lighting)
	lighting.FogEnd = 500
	return place
end

-- no spawn at all
function Maps.noSpawn()
	local place = Instance.new("DataModel")
	local map = new("Folder", { Name = "Map" }, place:GetService("Workspace"))
	map:SetAttribute("Seed", 1)
	folders(map, ALL)
	configured(map.Architecture, { Name = "Floor" })
	return place
end

return Maps
