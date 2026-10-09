-- Test places for the audit: Places.bad() has one of every problem audit_studio.luau looks
-- for, Places.clean() is a tidy small map that must produce no findings.

local roblox = require("@lune/roblox")

local Instance, Enum, Vector3 = roblox.Instance, roblox.Enum, roblox.Vector3

local function new(className, props, parent)
	local instance = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function part(parent, props)
	local p = new("Part", { Anchored = true, Size = Vector3.new(8, 1, 8) }, parent)
	for key, value in props or {} do
		p[key] = value
	end
	return p
end

local Places = {}

-- clean: anchored kit, few shadow lights, modest particles, streaming on
function Places.clean()
	local clean = Instance.new("DataModel")
	local ws = clean:GetService("Workspace")
	ws.StreamingEnabled = true
	ws.PlayerCharacterDestroyBehavior = Enum.PlayerCharacterDestroyBehavior.Enabled
	local map = new("Model", { Name = "Map" }, ws)
	for i = 1, 50 do
		part(map, { Name = `Floor{i}`, Position = Vector3.new(i * 8, 0, 0) })
	end
	local lamp = part(map, { Name = "Lamp", Size = Vector3.new(1, 6, 1) })
	new("PointLight", { Shadows = true, Range = 16 }, lamp)
	local fire = part(map, { Name = "Campfire", Size = Vector3.new(4, 1, 4) })
	new("ParticleEmitter", { Rate = 20 }, fire)
	new("Script", { Name = "Server", Source = "print('hello')" }, clean:GetService("ServerScriptService"))
	new("BloomEffect", {}, clean:GetService("Lighting"))
	return clean
end

-- bad: one of every problem; also returns the backdoored car model
function Places.bad()
	local bad = Instance.new("DataModel")
	local car
	local ws = bad:GetService("Workspace")
	ws.StreamingEnabled = false
	ws.PlayerCharacterDestroyBehavior = Enum.PlayerCharacterDestroyBehavior.Disabled
	bad:GetService("ServerScriptService").LoadStringEnabled = true

	-- Toolbox "free car" with a backdoor
	car = new("Model", { Name = "FreeCar" }, ws)
	part(car, { Name = "Body", Anchored = false })
	new("Script", { Name = "Engine", Source = "local a = 1\nrequire(4815162342)\n" }, car)
	new("Script", { Name = "Lights", Source = "print('lights on')" }, car)

	-- huge flat model without streaming
	local city = new("Model", { Name = "City" }, ws)
	for i = 1, 3100 do
		part(city, { Name = "Block", Size = Vector3.new(4, 4, 4), Position = Vector3.new(i % 100 * 4, 0, i // 100 * 4) })
	end
	for i = 1, 17000 do
		part(ws, { Name = "Pebble", Size = Vector3.new(0.5, 0.5, 0.5), Transparency = 0.5 })
	end

	-- precise meshes, shadow lights, particles, NPCs, stacked post-fx
	for i = 1, 60 do
		local mesh = new("MeshPart", { Anchored = true }, ws)
		mesh.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
	end
	for i = 1, 12 do
		local lamp = part(ws, { Name = `Lamp{i}` })
		new("PointLight", { Shadows = true }, lamp)
	end
	local vfx = part(ws, { Name = "Fountain" })
	new("ParticleEmitter", { Name = "Spray", Rate = 600 }, vfx)
	new("ParticleEmitter", { Name = "Mist", Rate = 250, Lifetime = roblox.NumberRange.new(5, 30) }, vfx)
	new("ParticleEmitter", { Name = "Sparks", Rate = 900 }, vfx)
	for i = 1, 45 do
		local npc = new("Model", { Name = `Zombie{i}` }, ws)
		part(npc, { Name = "HumanoidRootPart", Anchored = false })
		new("Humanoid", {}, npc)
	end
	new("BloomEffect", {}, bad:GetService("Lighting"))
	new("BloomEffect", {}, bad:GetService("Lighting"))

	return bad, car
end

return Places
