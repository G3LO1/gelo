-- Builds every Vfx preset into a showcase model you can drag into Studio to look at the
-- effects (particles render in Edit mode): one pad per preset, one-shot bursts turned into
-- a slow loop so they keep playing. Presets with colour variants get one pad per variant
-- (ElementBurst_Fire, ElementBurst_Frost). Every property is checked against Roblox's API
-- database on the way (Lune's @lune/roblox), so a typo in a preset fails here, not in the game.
--
-- Usage: lune run vfx_showcase.luau <Vfx.luau> [out.rbxmx] [--quality 0..1] [--reduced-flashing]
--                                   [--texture Name=content-id]... [--list]
--   --texture  fills Vfx.Textures for this model only, e.g. Burst4x4=rbxassetid://123, or a
--              local preview before uploading: Burst4x4=rbxasset://textures/gelo/burst_4x4.png
--              (copy the PNG into Studio's content/textures/gelo folder first)
--   --list     prints every pad's layers: particles per burst (or per second), flipbook state

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local USAGE =
	"usage: lune run vfx_showcase.luau <Vfx.luau> [out.rbxmx] [--quality 0..1] [--reduced-flashing] [--texture Name=id]... [--list]"
local args = process.args
local vfxPath = args[1]
if not vfxPath then
	print(USAGE)
	process.exit(2)
end
local outPath, quality, reduced, list = nil, 1, false, false
local textures = {}
local i = 2
while i <= #args do
	if args[i] == "--quality" then
		quality = tonumber(args[i + 1]) or 1
		i += 2
	elseif args[i] == "--reduced-flashing" then
		reduced = true
		i += 1
	elseif args[i] == "--list" then
		list = true
		i += 1
	elseif args[i] == "--texture" then
		local key, value = string.match(args[i + 1] or "", "^([%w_]+)=(.+)$")
		if not key then
			print(`--texture expects Name=content-id, got "{args[i + 1]}"`)
			process.exit(2)
		end
		textures[key] = value
		i += 2
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
for key, value in textures do
	if Vfx.Textures[key] == nil then
		print(`--texture {key}: Vfx.Textures has no such entry`)
		process.exit(2)
	end
	Vfx.Textures[key] = value
end
local model = roblox.Instance.new("Model")
model.Name = "VfxShowcase"
local names = {}
for name in Vfx.Presets do
	table.insert(names, name)
end
table.sort(names)

-- one pad per preset, or one per colour variant
local pads = {}
for _, name in names do
	local variants = if Vfx.variants then Vfx.variants(name) else {}
	if #variants == 0 then
		table.insert(pads, { pad = name, preset = name })
	end
	for _, variant in variants do
		table.insert(pads, { pad = `{name}_{variant}`, preset = name, variant = variant })
	end
end

local problems, lines = {}, {}
for index, entry in pads do
	local ok, err = pcall(function()
		local pad = roblox.Instance.new("Part")
		pad.Name = entry.pad
		pad.Anchored = true
		pad.Size = roblox.Vector3.new(6, 1, 6)
		pad.Position = roblox.Vector3.new((index - 1) * 12, 0.5, 0)
		pad.Color = roblox.Color3.fromRGB(45, 48, 56)
		pad.Parent = model
		local attachment =
			Vfx.build(entry.preset, { quality = quality, reducedFlashing = reduced, variant = entry.variant })
		attachment.Position = roblox.Vector3.new(0, 3, 0)
		attachment.Parent = pad
		for _, child in attachment:GetChildren() do
			if child:IsA("Attachment") then
				-- trail end points must sit directly under the part
				child.Position += attachment.Position
				child.Parent = pad
			end
		end
		local layers = {}
		for _, child in attachment:GetChildren() do
			if child:IsA("ParticleEmitter") then
				local burst = child:GetAttribute("Burst") or 0
				local label = child:GetAttribute("Layer") or child.Name
				local count = if burst > 0 then `{burst}` else `{child.Rate}/s`
				local flipbook = if child.FlipbookLayout ~= roblox.Enum.ParticleFlipbookLayout.None
					then ` {child.FlipbookLayout.Name} {child.FlipbookMode.Name}`
					else ""
				table.insert(layers, `{label} {count}{flipbook}`)
				if not child.Enabled then
					child.Rate = math.max(1, math.floor(burst / 1.5))
					child.Enabled = true
				end
			elseif child:IsA("PointLight") then
				table.insert(layers, "light")
			elseif child:IsA("Trail") then
				table.insert(layers, "trail")
			end
		end
		table.insert(lines, `  {entry.pad}: {table.concat(layers, ", ")}`)
	end)
	if not ok then
		table.insert(problems, `{entry.pad}: {string.match(tostring(err), "[^\n]+")}`)
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
if list then
	print(`quality {quality}, reduced flashing {if reduced then "on" else "off"}`)
	for _, line in lines do
		print(line)
	end
end
print(`OK: {#names} presets ({#pads} pads) build with valid properties`)
