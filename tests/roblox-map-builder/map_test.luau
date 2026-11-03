-- validate_map.luau, Scatter.luau and LightingPresets.luau behaviour, run under Lune with
-- Roblox's real API database (invalid property names, types and enums throw).
-- Usage (repo root): lune run tests/roblox-map-builder/map_test <out-dir>

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Maps = require("./places")

local out = process.args[1] or "."
local SKILL = "plugins/roblox-studio/skills/roblox-map-builder"

local passed, failed = 0, 0
local function check(condition, message)
	if condition then
		passed += 1
		print(`  ok   {message}`)
	else
		failed += 1
		print(`  FAIL {message}`)
	end
end

local env = {
	Instance = roblox.Instance,
	Enum = roblox.Enum,
	Color3 = roblox.Color3,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
}
local function load(path, extra)
	local environment = table.clone(env)
	for key, value in extra or {} do
		environment[key] = value
	end
	return luau.load(fs.readFile(path), { debugName = path, environment = environment })()
end

local function rules(report, ignore)
	local list = {}
	for _, finding in report.findings do
		if not (ignore and ignore[finding.rule]) then
			table.insert(list, `{finding.severity}:{finding.rule}`)
		end
	end
	table.sort(list)
	return list
end

local function sameSet(actual, expected)
	table.sort(expected)
	return table.concat(actual, ",") == table.concat(expected, ","), table.concat(actual, ", ")
end

local function has(report, rule)
	for _, finding in report.findings do
		if finding.rule == rule then
			return true
		end
	end
	return false
end

print("validate_map")
local Validator = load(`{SKILL}/scripts/validate_map.luau`, { MAP_RETURN = true })
local defaults = table.clone(Validator.Thresholds)

local clean = Maps.clean()
local cleanReport = Validator.run(clean, { raycast = false, pathfinding = false })
check(#cleanReport.findings == 0, `clean map: no findings ({table.concat(rules(cleanReport), ", ")})`)
check(cleanReport.stats.spawns == 1 and cleanReport.stats.goals == 1, "clean map: spawn and goal counted")
local skippedText = table.concat(cleanReport.skipped, "|")
check(string.find(skippedText, "pathfinding", 1, true) ~= nil and string.find(skippedText, "spawn ground", 1, true) ~= nil, "no raycasts: ground and pathfinding checks are reported as skipped, not passed")

for key, value in Maps.badThresholds do
	Validator.Thresholds[key] = value
end
local bad = Maps.bad()
local badReport = Validator.run(bad, { raycast = false, pathfinding = false })
local BAD = {
	"high:SPAWN-BLOCKED",
	"medium:DOOR-TOO-SMALL",
	"medium:NO-STREAMING",
	"medium:UNANCHORED",
	"medium:Z-FIGHTING",
	"low:FOG-IGNORED",
	"low:GOALS-UNTAGGED",
	"low:MAP-FOLDERS",
	"low:MAP-SEED",
	"low:NEON-NO-LIGHT",
	"low:STACKED-POSTFX",
	"low:TINY-COLLIDABLE",
}
local ok, got = sameSet(rules(badReport), table.clone(BAD))
check(ok, `bad map: every rule fires exactly once ({got})`)
local text, totals = Validator.format(badReport)
check(totals.high == 1 and string.find(text, "LowCeiling", 1, true) ~= nil, "report names the part blocking the spawn")
check(string.find(text, "Slab", 1, true) ~= nil and string.find(text, "Rug", 1, true) ~= nil, "report names the z-fighting pair")
check(string.find(text, "Crate", 1, true) ~= nil, "report names the unanchored part")
for key, value in defaults do
	Validator.Thresholds[key] = value
end

local dynamic = Maps.bad()
dynamic:GetService("Workspace").Map.Props.Crate:AddTag("Dynamic")
check(not has(Validator.run(dynamic, { raycast = false, pathfinding = false }), "UNANCHORED"), 'a part tagged "Dynamic" is not reported as unanchored')

check(has(Validator.run(Maps.noSpawn(), { raycast = false, pathfinding = false }), "SPAWN-NONE"), "map without a SpawnLocation: SPAWN-NONE")

local empty = roblox.Instance.new("DataModel")
check(has(Validator.run(empty, { raycast = false, pathfinding = false }), "MAP-ROOT"), "no Workspace.Map: MAP-ROOT")

-- the opening is tested with its own dimensions: 6 x 9 passes, 3 x 6 fails
local doorOnly = Maps.clean()
local doorPart = doorOnly:GetService("Workspace").Map.Architecture.DoorOpening
doorPart.Size = roblox.Vector3.new(3, 6, 1)
check(has(Validator.run(doorOnly, { raycast = false, pathfinding = false }), "DOOR-TOO-SMALL"), "a 3 x 6 opening is too small")

-- same colour and material coplanar faces are not flagged (nothing flickers visibly)
local sameColor = Maps.bad()
local arch = sameColor:GetService("Workspace").Map.Architecture
arch.Rug.Color = arch.Slab.Color
check(not has(Validator.run(sameColor, { raycast = false, pathfinding = false }), "Z-FIGHTING"), "coplanar parts with the same colour and material are not flagged")

print("saved and loaded again")
fs.writeFile(`{out}/clean.rbxl`, roblox.serializePlace(clean))
fs.writeFile(`{out}/bad.rbxl`, roblox.serializePlace(bad))
-- Tags are not asserted on (a loader may drop them); everything else must survive.
local tagRules = { ["DOOR-TOO-SMALL"] = true, ["GOALS-UNTAGGED"] = true }
for key, value in Maps.badThresholds do
	Validator.Thresholds[key] = value
end
local loadedBad = Validator.run(roblox.deserializePlace(fs.readFile(`{out}/bad.rbxl`)), { raycast = false, pathfinding = false })
local expected = {}
for _, rule in BAD do
	if not tagRules[string.match(rule, ":(.+)$")] then
		table.insert(expected, rule)
	end
end
ok, got = sameSet(rules(loadedBad, tagRules), expected)
check(ok, `bad.rbxl: same findings ({got})`)
for key, value in defaults do
	Validator.Thresholds[key] = value
end
local loadedClean = Validator.run(roblox.deserializePlace(fs.readFile(`{out}/clean.rbxl`)), { raycast = false, pathfinding = false })
local cleanIgnore = { ["DOOR-TOO-SMALL"] = true, ["GOALS-UNTAGGED"] = true, ["MAP-SEED"] = true }
check(#rules(loadedClean, cleanIgnore) == 0, `clean.rbxl: no findings ({table.concat(rules(loadedClean, cleanIgnore), ", ")})`)

print("Scatter")
local Scatter = load(`{SKILL}/assets/Scatter.luau`)
local rng = Scatter.newRandom(1)
check(math.abs(rng() - 96541 / 2147483646) < 1e-12, "Park-Miller generator is pinned (same numbers on every platform)")

local function flat()
	return 0, 1
end
local function dist(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end
local base = { seed = 42, minX = -100, maxX = 100, minZ = -100, maxZ = 100, count = 60, spacing = 8, sample = flat }

local a = Scatter.generate(base)
local b = Scatter.generate(base)
local repeatable = #a == #b
for i = 1, #a do
	if not b[i] or a[i].x ~= b[i].x or a[i].z ~= b[i].z or a[i].yaw ~= b[i].yaw then
		repeatable = false
	end
end
check(repeatable and #a == 60, "same seed: same 60 placements")
base.seed = 43
local different = Scatter.generate(base)
check(different[1].x ~= a[1].x, "different seed: different placements")
base.seed = 42

local spaced = true
for i = 1, #a do
	for j = i + 1, #a do
		if dist(a[i], a[j]) < 8 then
			spaced = false
		end
	end
end
check(spaced, "every pair is at least `spacing` apart")

local zone = { x = 0, z = 0, radius = 30 }
local ex = table.clone(base)
ex.exclude = { zone }
local excluded = Scatter.generate(ex)
local clear = true
for _, p in excluded do
	if dist(p, zone) < zone.radius then
		clear = false
	end
end
check(clear and #excluded > 0, "exclusion circle stays empty")

local slope = table.clone(base)
slope.sample = function(x)
	return 0, if x > 0 then 0.5 else 0.95
end
slope.minNormalY = 0.8
local gentle = Scatter.generate(slope)
local onlyLeft = #gentle > 0
for _, p in gentle do
	if p.x > 0 then
		onlyLeft = false
	end
end
check(onlyLeft, "slope limit: nothing on the steep half")

local band = table.clone(base)
band.sample = function(x)
	return x, 1
end
band.minY = -20
band.maxY = 20
local banded = Scatter.generate(band)
local inBand = #banded > 0
for _, p in banded do
	if p.y < -20 or p.y > 20 then
		inBand = false
	end
end
check(inBand, "height band respected")

local groves = table.clone(base)
groves.groves = { { x = 50, z = 50, radius = 20 } }
groves.count = 10
local grouped = Scatter.generate(groves)
local inside = #grouped > 0
for _, p in grouped do
	if dist(p, groves.groves[1]) > 20 then
		inside = false
	end
end
check(inside, "grove: placements fall inside the grove")

local second = table.clone(base)
second.seed = 7
second.existing = a
local more = Scatter.generate(second)
local spacedFromFirst = #more > 0
for _, p in more do
	for _, q in a do
		if dist(p, q) < 8 then
			spacedFromFirst = false
		end
	end
end
check(spacedFromFirst, "second pass keeps its distance from the first")

local nowhere = table.clone(base)
nowhere.sample = function()
	return nil
end
local none, rejected = Scatter.generate(nowhere)
check(#none == 0 and rejected.noGround > 0, "no ground: nothing placed, rejections counted")

local packed = table.clone(base)
packed.minX, packed.maxX, packed.minZ, packed.maxZ = 0, 10, 0, 10
packed.count = 100
local few = Scatter.generate(packed)
check(#few < 100 and #few >= 1, `tiny area: stops short instead of looping ({#few} placed)`)

print("LightingPresets")
local Presets = load(`{SKILL}/assets/LightingPresets.luau`)
local names = Presets.names()
check(#names >= 10, `{#names} presets`)

local function lightingOf(place)
	return place:GetService("Lighting")
end
local function tolerated(entry)
	-- properties that older API databases may not have yet
	return string.find(entry, "LightingStyle", 1, true) or string.find(entry, "PrioritizeLightingQuality", 1, true)
end
local allApply, allClean = true, true
for _, name in names do
	local place = roblox.Instance.new("DataModel")
	local lighting = lightingOf(place)
	local okApply, report = pcall(Presets.apply, lighting, name)
	if not okApply then
		allApply = false
		print(`    {name}: {report}`)
	else
		for _, entry in report.skipped do
			if not tolerated(entry) then
				allClean = false
				print(`    {name}: {entry}`)
			end
		end
	end
end
check(allApply, "every preset applies")
check(allClean, "every property name, type and enum is valid in Roblox's API database")

local place = roblox.Instance.new("DataModel")
local lighting = lightingOf(place)
roblox.Instance.new("BloomEffect").Parent = lighting
roblox.Instance.new("BloomEffect").Parent = lighting
roblox.Instance.new("Atmosphere").Parent = lighting
local report = Presets.apply(lighting, "LowPoly")
local blooms, atmospheres = 0, 0
for _, child in lighting:GetChildren() do
	if child.ClassName == "BloomEffect" then
		blooms += 1
	elseif child.ClassName == "Atmosphere" then
		atmospheres += 1
	end
end
check(blooms == 1 and atmospheres == 1, "template effects are reused and duplicates removed, never stacked")
check(#report.removed == 1, "the removed duplicate is reported")
Presets.apply(lighting, "LowPoly")
check(#lighting:GetChildren() == 3 and lighting.Brightness == 2 and lighting.ClockTime == 14, "applying twice changes nothing")
check(math.round(lighting.OutdoorAmbient.R * 255) == 0xA9 and math.round(lighting.Ambient.G * 255) == 0x7A, "colors from hex are exact")

Presets.apply(lighting, "Retro")
local left = {}
for _, child in lighting:GetChildren() do
	table.insert(left, child.ClassName)
end
check(not table.find(left, "BloomEffect") and not table.find(left, "SunRaysEffect"), "Retro strips bloom and sun rays")

check(not pcall(Presets.apply, lighting, "Nope"), "unknown preset is an error that lists the names")

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
