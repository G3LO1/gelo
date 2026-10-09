-- Runs audit_studio.luau on a place or model file, outside Studio.
--
-- Usage: lune run audit_place.luau <file.rbxl|.rbxlx|.rbxm|.rbxmx> [--dump-scripts <dir>] [--json <out.json>] [--fail-on high|medium|low|none]
--   --dump-scripts  writes every script's source to <dir>/<Service>/<Path>.<server|client>.luau so
--                   scan_luau.py can read them (binary files have no readable sources otherwise)
--   --fail-on       exit code 1 if a finding at or above this severity exists (default: none)
-- Rojo projects: `rojo build -o place.rbxl` first.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local args = process.args
local file = args[1]
if not file then
	print("usage: lune run audit_place.luau <file.rbxl|.rbxlx|.rbxm|.rbxmx> [--dump-scripts <dir>] [--json <out.json>] [--fail-on high|medium|low|none]")
	process.exit(2)
end
local options = {}
local i = 2
while i <= #args do
	options[string.gsub(args[i], "^%-%-", "")] = args[i + 1]
	i += 2
end

local contents = fs.readFile(file)
local game
if string.match(file, "%.rbxlx?$") then
	game = roblox.deserializePlace(contents)
else
	game = roblox.Instance.new("DataModel")
	for _, instance in roblox.deserializeModel(contents) do
		instance.Parent = game:GetService("Workspace")
	end
end

local here = string.match(process.args[0] or "", "^(.*)[/\\]") or ""
local scriptDir = string.match(debug.info(1, "s"), "^(.*)[/\\]") or here
local corePath = (scriptDir ~= "" and scriptDir .. "/" or "") .. "audit_studio.luau"
local chunk = luau.load(fs.readFile(corePath), {
	debugName = "audit_studio",
	environment = {
		AUDIT_RETURN = true,
		Enum = roblox.Enum,
	},
})
local Audit = chunk()
local report = Audit.run(game)
local text, totals = Audit.format(report)
print(text)

if options["dump-scripts"] then
	local root = options["dump-scripts"]
	local written = 0
	local used = {}
	for _, script in game:GetDescendants() do
		if script:IsA("LuaSourceContainer") then
			local ok, source = pcall(function()
				return script.Source
			end)
			if ok and source then
				local parts = string.split(script:GetFullName(), ".")
				for index, part in parts do
					parts[index] = string.gsub(part, "[^%w_%-]", "_")
				end
				local kind = if script.ClassName == "LocalScript" then ".client" elseif script.ClassName == "Script" then ".server" else ""
				local dir = root .. "/" .. table.concat(parts, "/", 1, #parts - 1)
				local base = dir .. "/" .. parts[#parts] .. kind
				local target = base .. ".luau"
				local n = 1
				while used[target] do
					n += 1
					target = `{base}_{n}.luau`
				end
				used[target] = true
				fs.writeDir(dir)
				fs.writeFile(target, source)
				written += 1
			end
		end
	end
	print(`dumped {written} script(s) to {root}: python3 scan_luau.py {root}`)
end

if options.json then
	fs.writeFile(options.json, serde.encode("json", report, true))
end

local failOn = options["fail-on"] or "none"
local levels = { high = { "high" }, medium = { "high", "medium" }, low = { "high", "medium", "low" }, none = {} }
for _, level in levels[failOn] or {} do
	if totals[level] > 0 then
		process.exit(1)
	end
end
