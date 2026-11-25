-- AnimCheck.luau under Lune with Roblox's API database: published clips (real KeyframeSequence /
-- Keyframe / KeyframeMarker instances) checked against manifest specs, R15 and R6.
-- Usage (repo root): lune run tests/roblox-animation-vfx/animcheck_test <generated example Animations.luau>

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Enum = roblox.Enum
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

local AnimCheck = luau.load(fs.readFile("plugins/roblox-studio/skills/roblox-animation-vfx/assets/AnimCheck.luau"), {
	debugName = "AnimCheck",
	environment = { game = { GetService = function() error("tests pass a provider") end }, print = function() end },
})()

local function clip(loop, priority, keyframes)
	local sequence = roblox.Instance.new("KeyframeSequence")
	sequence.Loop = loop
	sequence.Priority = priority
	for _, k in keyframes do
		local keyframe = roblox.Instance.new("Keyframe")
		keyframe.Time = k[1]
		for _, name in k[2] or {} do
			local marker = roblox.Instance.new("KeyframeMarker")
			marker.Name = name
			marker.Parent = keyframe
		end
		keyframe.Parent = sequence
	end
	return sequence
end

local published = {
	["rbxassetid://11"] = clip(true, Enum.AnimationPriority.Movement, { { 0, { "Footstep" } }, { 0.4, { "Footstep" } }, { 0.8 } }),
	["rbxassetid://12"] = clip(false, Enum.AnimationPriority.Action, { { 0 }, { 0.37 }, { 0.67 } }), -- Hit lost on import
	["rbxassetid://21"] = clip(false, Enum.AnimationPriority.Movement, { { 0, { "Footstep" } }, { 0.8 } }), -- R6 walk saved unlooped
	["rbxassetid://22"] = clip(false, Enum.AnimationPriority.Action, { { 0 }, { 0.37, { "Hit" } }, { 0.67 } }),
}
local provider = {
	GetAnimationClipAsync = function(_, id)
		local found = published[id]
		if not found then
			error("HTTP 403 (Forbidden)")
		end
		return found
	end,
}

local markers, length = AnimCheck.collect(published["rbxassetid://11"])
check(markers.Footstep == 0 and math.abs(length - 0.8) < 1e-6, "collect(): marker times and clip length from a KeyframeSequence")

local P = Enum.AnimationPriority
local specs = {
	Walk = { Id = "rbxassetid://11", Priority = P.Movement, Looped = true, Markers = { "Footstep" } },
	Chop = { Id = "rbxassetid://12", Priority = P.Action, Looped = false, Markers = { "Hit" } },
	Locomotion = { Id = "rbxassetid://99", Graph = true, Markers = {} },
}
local specsR6 = {
	Walk = { Id = "rbxassetid://21", Priority = P.Movement, Looped = true, Markers = { "Footstep" } },
	Chop = { Id = "rbxassetid://22", Priority = P.Action2, Looped = false, Markers = { "Hit" } },
	Wave = { Id = "rbxassetid://23", Priority = P.Action, Looped = false, Markers = {} },
}
local lines = {}
local result = AnimCheck.runAll({ Specs = specs, SpecsR6 = specsR6 }, { provider = provider, print = function(line) table.insert(lines, line) end })
local function said(needle)
	for _, problem in result.problems do
		if string.find(problem, needle, 1, true) then
			return true
		end
	end
	return false
end
check(result.checked == 4, `4 published clips checked, graphs skipped ({result.checked})`)
check(said('Specs.Chop: marker "Hit" is missing on the published clip'), "a marker lost on import is reported")
check(not said("Specs.Walk"), "a clip that matches the manifest has no problems")
check(said("SpecsR6.Walk: published with Loop = false, the manifest says true"), "R6: looping saved wrong")
check(said("SpecsR6.Chop: published at Enum.AnimationPriority.Action, the manifest says Enum.AnimationPriority.Action2"), "R6: priority saved wrong")
check(said("SpecsR6.Wave: can't load rbxassetid://23") and said("published by the owner"), "an id that won't load points at ownership/permissions")
check(#result.problems == 4 and #lines == 6, `4 problems, one line each plus a summary per rig ({#result.problems}, {#lines} lines)`)

-- the module generated from the example manifest: R15 + R6 specs, ids not uploaded yet
local generated = luau.load(fs.readFile(process.args[1]), {
	debugName = "ExampleAnimations",
	environment = { Enum = Enum },
})()
check(generated.SpecsR6 ~= nil and generated.Specs.Walk and generated.SpecsR6.Chop, "example manifest: Specs and SpecsR6")
local fakeR6 = { RigType = Enum.HumanoidRigType.R6 }
local fakeR15 = { RigType = Enum.HumanoidRigType.R15 }
check(generated.specsFor(fakeR6) == generated.SpecsR6 and generated.specsFor(fakeR15) == generated.Specs and generated.specsFor(nil) == generated.Specs, "specsFor(humanoid) picks the rig's specs")
local todo = AnimCheck.runAll(generated, { provider = provider, print = function() end })
check(todo.checked == 0 and #todo.problems == 4, "ids still 0: every clip reported as not uploaded yet")

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
