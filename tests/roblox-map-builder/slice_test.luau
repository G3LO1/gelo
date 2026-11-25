-- slice_check.luau on built test slices (Roblox instances under Lune): the good house passes and
-- yields a 4-viewpoint walkthrough scene; every broken variant is reported for its own reason.
-- Also writes good.rbxm and lowdoor.rbxm for the command-line test.
-- Usage (repo root): lune run tests/roblox-map-builder/slice_test <tmp dir>

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Slices = require("./slices")
local SliceCheck = luau.load(fs.readFile("plugins/roblox-studio/skills/roblox-map-builder/scripts/slice_check.luau"), {
	debugName = "slice_check",
	environment = { SLICE_RETURN = true, Vector3 = roblox.Vector3 },
})()

local passed, failed = 0, 0
local function check(condition, message, report)
	if condition then
		passed += 1
		print(`  ok   {message}`)
	else
		failed += 1
		print(`  FAIL {message}`)
		if report then
			print("       " .. string.gsub(SliceCheck.format(report), "\n", "\n       "))
		end
	end
end
local function has(report, level, needle)
	for _, line in report.lines do
		if line[1] == level and string.find(line[2], needle, 1, true) then
			return true
		end
	end
	return false
end
local function fails(report)
	local n = 0
	for _, line in report.lines do
		n += if line[1] == "FAIL" then 1 else 0
	end
	return n
end

print("good slice")
local _, slice = Slices.good()
local report = SliceCheck.run(slice)
check(fails(report) == 0, "no failures", report)
check(has(report, "PASS", "door FrontDoor: 4 x 8 studs fits the avatar"), "door fits the avatar", report)
check(has(report, "PASS", "route: 4 markers walkable at avatar size, in through the door"), "route walkable, in through the door", report)
check(has(report, "PASS", "interior Hall: 12 studs clear height"), "interior height", report)
check(has(report, "PASS", "viewpoint Entrance at eye height (4.8 studs)") and has(report, "PASS", "viewpoint Scale at eye height"), "four eye-height viewpoints", report)
check(has(report, "INFO", "16 kit pieces, 4 module(s), grid 4"), "kit counted: 16 pieces, 4 modules (corner joints are not overlaps)", report)
local scene = report.scene
check(scene and #scene.camera == 4 and #scene.shots == 4 and scene.shots[1].name == "Entrance" and scene.shots[4].name == "Scale", "walkthrough scene: 4 camera keys and shots in Entrance, Route, Interior, Scale order")
check(scene and math.abs(scene.camera[1].position[2] - 4.8) < 1e-4 and scene.camera[3].at == 5 and scene.length == 7.5, "camera at the viewpoints' eye height, 2.5 s apart")

print("broken slices")
local expected = {
	lowdoor = "door FrontDoor: 6 studs high, the avatar needs 7",
	blocked = "route blocked by Crate",
	nofloor = "no floor under the route",
	step = "step of 4 studs up",
	noview = 'no Viewpoint with View = "Scale"',
	eye = "viewpoint Interior: 8 studs above the floor",
	offgrid = "kit piece Roof2 (Roof8): bottom center (13.0, 13.0, 4.0) is off the 4-stud grid",
	size = "module Wall8 has 2 different sizes",
	overlap = "overlap (4 x 1 x 8 studs)",
	turned = "kit piece WallS1 (Wall8): turned 45 degrees",
	lowceiling = "interior Hall: 8 studs to the ceiling, MinCeiling is 9",
	nodoor = "the route never goes through a doorway",
}
for _, name in Slices.cases do
	local _, broken = Slices.broken(name)
	local r = SliceCheck.run(broken)
	check(expected[name] and has(r, "FAIL", expected[name]), `{name}: "{expected[name]}"`, r)
end

local tmp = process.args[1]
local goodGame = Slices.good()
fs.writeFile(`{tmp}/good.rbxl`, roblox.serializePlace(goodGame))
local _, lowdoor = Slices.broken("lowdoor")
fs.writeFile(`{tmp}/lowdoor.rbxm`, roblox.serializeModel({ lowdoor.Parent }))

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
