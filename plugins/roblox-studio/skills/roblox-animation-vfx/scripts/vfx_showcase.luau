-- Builds every Vfx preset into a showcase model you can drag into Studio to look at the
-- effects (particles render in Edit mode): one pad per preset, one-shot bursts turned into
-- a slow loop so they keep playing. Every property is checked against Roblox's API database
-- on the way (Lune's @lune/roblox), so a typo in a preset fails here, not in the game.
--
-- Usage: lune run vfx_showcase.luau <Vfx.luau> [out.rbxmx] [--quality 0..1] [--reduced-flashing]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local args = process.args
local vfxPath = args[1]
if not vfxPath then
	print("usage: lune run vfx_showcase.luau <Vfx.luau> [out.rbxmx] [--quality 0..1] [--reduced-flashing]")
	process.exit(2)
end
local outPath, quality, reduced = nil, 1, false
local i = 2
while i <= #args do
	if args[i] == "--quality" then
		quality = tonumber(args[i + 1]) or 1
		i += 2
	elseif args[i] == "--reduced-flashing" then
		reduced = true
		i += 1
	else
		outPath = args[i]
		i += 1
	end
end

local function loadVfx(path: string)
	return luau.load(fs.readFile(path), {
		debugName = "Vfx",
		environment = {
			Instance = roblox.Instance,
			Enum = roblox.Enum,
			Color3 = roblox.Color3,
			Vector2 = roblox.Vector2,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			NumberRange = roblox.NumberRange,
			NumberSequence = roblox.NumberSequence,
			NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
			ColorSequence = roblox.ColorSequence,
			ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		},
	})()
end

local Vfx = loadVfx(vfxPath)
local model = roblox.Instance.new("Model")
model.Name = "VfxShowcase"
local names = {}
for name in Vfx.Presets do
	table.insert(names, name)
end
table.sort(names)

local problems = {}
for index, name in names do
	local ok, err = pcall(function()
		local pad = roblox.Instance.new("Part")
		pad.Name = name
		pad.Anchored = true
		pad.Size = roblox.Vector3.new(6, 1, 6)
		pad.Position = roblox.Vector3.new((index - 1) * 12, 0.5, 0)
		pad.Color = roblox.Color3.fromRGB(45, 48, 56)
		pad.Parent = model
		local attachment = Vfx.build(name, { quality = quality, reducedFlashing = reduced })
		attachment.Position = roblox.Vector3.new(0, 3, 0)
		attachment.Parent = pad
		for _, child in attachment:GetChildren() do
			if child:IsA("Attachment") then
				-- trail end points must sit directly under the part
				child.Position += attachment.Position
				child.Parent = pad
			end
		end
		for _, emitter in attachment:GetChildren() do
			if emitter:IsA("ParticleEmitter") and not emitter.Enabled then
				local burst = emitter:GetAttribute("Burst") or 0
				emitter.Rate = math.max(1, math.floor(burst / 1.5))
				emitter.Enabled = true
			end
		end
	end)
	if not ok then
		table.insert(problems, `{name}: {string.match(tostring(err), "[^\n]+")}`)
	end
end

if #problems > 0 then
	print(`FAILED: {#problems} preset(s) have invalid properties`)
	for _, problem in problems do
		print(`  - {problem}`)
	end
	process.exit(1)
end
if outPath then
	fs.writeFile(outPath, roblox.serializeModel({ model }, true))
	print(`wrote {outPath}`)
end
print(`OK: {#names} presets build with valid properties`)
