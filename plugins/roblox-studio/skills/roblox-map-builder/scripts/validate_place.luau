-- Runs validate_map.luau on a place or model file, outside Studio.
--
-- Usage: lune run validate_place.luau <file.rbxl|.rbxlx|.rbxm|.rbxmx> [--json <out.json>] [--fail-on high|medium|low|none]
--   --fail-on   exit code 1 if a finding at or above this severity exists (default: none)
-- Lune has no raycasts or pathfinding, so spawn-on-ground, floating props and spawn -> goal
-- routes are listed as SKIPPED. Run validate_map.luau in Studio for those.
-- Rojo projects: `rojo build -o place.rbxl` first.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local args = process.args
local file = args[1]
if not file then
	print("usage: lune run validate_place.luau <file.rbxl|.rbxlx|.rbxm|.rbxmx> [--json <out.json>] [--fail-on high|medium|low|none]")
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

local scriptDir = string.match(debug.info(1, "s"), "^(.*)[/\\]") or ""
local corePath = (scriptDir ~= "" and scriptDir .. "/" or "") .. "validate_map.luau"
local Validator = luau.load(fs.readFile(corePath), {
	debugName = "validate_map",
	environment = {
		MAP_RETURN = true,
		Enum = roblox.Enum,
		Vector3 = roblox.Vector3,
	},
})()
local report = Validator.run(game, { raycast = false, pathfinding = false })
local text, totals = Validator.format(report)
print(text)

if options["json"] then
	fs.writeFile(options["json"], serde.encode("json", report, true))
end

local failOn = options["fail-on"] or "none"
local limit = if failOn == "high" then totals.high
	elseif failOn == "medium" then totals.high + totals.medium
	elseif failOn == "low" then totals.high + totals.medium + totals.low
	else 0
process.exit(if limit > 0 then 1 else 0)
