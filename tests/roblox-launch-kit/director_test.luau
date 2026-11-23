-- ShotDirector.luau under Lune with the Scenes module scene_spec.py generated from the example scene:
-- camera path, event timing, actors, readiness, the silent rehearsal behind a black screen, shots,
-- reset, and the same frames on every run. Engine services are small stand-ins; CFrame/Vector3 are
-- Roblox's (Lune). Note: Lune 0.10's CFrame.lookAt flips the Z of the look direction (Roblox doesn't),
-- so the test checks that the camera gets CFrame.lookAt(position, lookAt), not where that points.
-- Usage (repo root): lune run tests/roblox-launch-kit/director_test <generated Scenes.luau>

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

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
local function near(a, b, tolerance)
	return (a - b).Magnitude < (tolerance or 1e-3)
end

-- stand-in instances ---------------------------------------------------------------------------
local destroyed = {}
local created = {}
local function node(className, name)
	local n = { ClassName = className, Name = name or className, children = {}, pivot = roblox.CFrame.new() }
	table.insert(created, n)
	function n:IsA(c)
		return c == self.ClassName or (c == "BasePart" and self.ClassName == "Part") or (c == "LayerCollector" and self.ClassName == "ScreenGui")
	end
	function n:FindFirstChild(child, recursive)
		for _, c in self.children do
			if c.Name == child then
				return c
			end
			if recursive then
				local hit = c:FindFirstChild(child, true)
				if hit then
					return hit
				end
			end
		end
		return nil
	end
	function n:FindFirstChildWhichIsA(c, recursive)
		for _, child in self.children do
			if child:IsA(c) then
				return child
			end
			if recursive then
				local hit = child:FindFirstChildWhichIsA(c, true)
				if hit then
					return hit
				end
			end
		end
		return nil
	end
	function n:GetDescendants()
		local out = {}
		for _, c in self.children do
			table.insert(out, c)
			for _, d in c:GetDescendants() do
				table.insert(out, d)
			end
		end
		return out
	end
	function n:Add(child)
		child.Parent = self
		return child
	end
	function n:Clone()
		local copy = node(self.ClassName, self.Name)
		copy.template = self
		copy.LoadAnimation = self.LoadAnimation
		for _, c in self.children do
			copy:Add(c:Clone())
		end
		return copy
	end
	function n:PivotTo(cf)
		self.pivot = cf
	end
	function n:GetPivot()
		return self.pivot
	end
	function n:Destroy()
		destroyed[self] = true
		self.Parent = nil
	end
	-- `x.Parent = y` moves x into y's children, like Roblox
	return setmetatable(n, {
		__index = function(t, key)
			return if key == "Parent" then rawget(t, "_parent") else nil
		end,
		__newindex = function(t, key, value)
			if key ~= "Parent" then
				rawset(t, key, value)
				return
			end
			local old = rawget(t, "_parent")
			if old then
				local i = table.find(old.children, t)
				if i then
					table.remove(old.children, i)
				end
			end
			rawset(t, "_parent", value)
			if value then
				table.insert(value.children, t)
			end
		end,
	})
end

local played = {}
local function character(name)
	local model = node("Model", name)
	local humanoid = model:Add(node("Humanoid"))
	local animator = humanoid:Add(node("Animator"))
	function animator:LoadAnimation(animation)
		return { Play = function()
			table.insert(played, { model = self.Parent.Parent, id = animation.AnimationId })
		end }
	end
	model:Add(node("Part", "RightHand"))
	model.PrimaryPart = model:Add(node("Part", "HumanoidRootPart"))
	return model
end

local game = node("DataModel")
local assets = game:Add(node("Folder", "ReplicatedStorage")):Add(node("Folder", "SceneAssets"))
assets:Add(character("Hero"))
assets:Add(character("Rival"))
local world = node("Workspace")
world.StreamingEnabled = true
local streamed = {}
function world:RequestStreamAroundAsync(position)
	table.insert(streamed, position)
end
local playerGui = node("PlayerGui")
local preloaded = {}
local provider = { PreloadAsync = function(_, list)
	for _, item in list do
		table.insert(preloaded, item.Name)
	end
end }
local camera = { CameraType = roblox.Enum.CameraType.Custom, CameraSubject = "PlayerHumanoid", CFrame = roblox.CFrame.new(1, 2, 3), FieldOfView = 70 }

local env = {
	CFrame = roblox.CFrame,
	Vector3 = roblox.Vector3,
	UDim2 = roblox.UDim2,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
	Instance = { new = function(className)
		return node(className)
	end },
	math = math,
	string = string,
	table = table,
	pcall = pcall,
	tostring = tostring,
	warn = print,
}
local ShotDirector = luau.load(fs.readFile("plugins/roblox-studio/skills/roblox-launch-kit/assets/ShotDirector.luau"), { debugName = "ShotDirector", environment = env })()
local Scenes = luau.load(fs.readFile(process.args[1]), { debugName = "Scenes", environment = { Vector3 = roblox.Vector3 } })()
local scene = Scenes.SwordClash

print("camera path and timing")
local cf0, fov0 = ShotDirector.cameraAt(scene, 0)
local cfEnd, fovEnd = ShotDirector.cameraAt(scene, scene.Length)
check(near(cf0.Position, roblox.Vector3.new(0, 3, -26)) and fov0 == 50, "starts on the first key")
check(near(cfEnd.Position, roblox.Vector3.new(10, 6, -10)) and fovEnd == 40, "ends on the last key")
local mid = (scene.Camera[1].T + scene.Camera[2].T) / 2
local cfMid, fovMid = ShotDirector.cameraAt(scene, mid)
check(near(cfMid.Position, roblox.Vector3.new(-3, 3.5, -19)) and math.abs(fovMid - 47.5) < 1e-3, "eased halfway between keys (Sine: half the way at half the time)")
local quarter = ShotDirector.cameraAt(scene, scene.Camera[1].T + (scene.Camera[2].T - scene.Camera[1].T) / 4)
check((quarter.Position - cf0.Position).Magnitude < 0.25 * (roblox.Vector3.new(-6, 4, -12) - roblox.Vector3.new(0, 3, -26)).Magnitude, "Sine ease starts slow (less than a quarter of the way at a quarter of the time)")
local expected = roblox.CFrame.lookAt(scene.Camera[3].Position, scene.Camera[3].LookAt)
check(near(cfEnd.Position, expected.Position) and near(cfEnd.LookVector, expected.LookVector) and near(cfEnd.UpVector, expected.UpVector), "the camera frame is CFrame.lookAt(position, lookAt) of the key")
local due = ShotDirector.due(scene.Events, -1, 0)
check(#due == 1 and due[1].Name == "Walk" and #ShotDirector.due(scene.Events, 0, 0.9231) == 1 and #ShotDirector.due(scene.Events, 4.6, 4.62) == 2, "due(): events in (t0, t1], the ones at 0 on the first frame")

print("a full run: rehearsal behind a black screen, then the take")
local blackoutSeen = {}
local shots = {}
local vfx, sfx = {}, {}
local modules = {
	Vfx = { play = function(name, target)
		table.insert(vfx, { name = name, target = target })
	end },
	Sfx = { play = function(name, target)
		table.insert(sfx, { name = name, target = target })
	end },
	Animations = {
		Specs = { Walk = { Id = "rbxassetid://11" }, Chop = { Id = "rbxassetid://12" } },
		specsFor = function()
			return { Walk = { Id = "rbxassetid://11" }, Chop = { Id = "rbxassetid://12" } }
		end,
	},
}
local function run(extra)
	local options = {
		modules = modules,
		root = game,
		camera = camera,
		workspace = world,
		playerGui = playerGui,
		contentProvider = provider,
		step = function()
			return 1 / 30
		end,
		handlers = nil,
		onShot = function(shot, t, cam)
			table.insert(shots, { name = shot.Name, t = t, position = cam.CFrame.Position, fov = cam.FieldOfView })
		end,
		log = function() end,
	}
	for k, v in extra or {} do
		options[k] = v
	end
	return ShotDirector.run(scene, options)
end
-- watch the black screen from inside the events
modules.Vfx.play = function(name, target)
	table.insert(vfx, { name = name, target = target })
	table.insert(blackoutSeen, playerGui:FindFirstChild("SceneRehearsal") ~= nil and not destroyed[playerGui:FindFirstChild("SceneRehearsal")])
end
local result = run()
check(result.ready and #result.missing == 0 and result.error == nil, "ready: every template and preload path found")
check(table.concat(preloaded, ",") == "Hero,Rival" and #streamed == 3, "preloaded the scene assets and streamed around all 3 camera keys")
check(#result.fired.rehearsal == 5 and #result.fired.take == 7, "rehearsal fires every event but the 2 sounds (5), the take all 7")
check(#sfx == 2 and sfx[2].name == "SwordHit" and sfx[2].target.Name == "RightHand", "sounds only in the take, from the hand")
check(blackoutSeen[1] == true and blackoutSeen[#blackoutSeen] == false, "effects in the rehearsal happen behind the black screen; the take is visible")
check(#played == 4 and played[1].id == "rbxassetid://11" and played[2].id == "rbxassetid://12", "animations play on the actors' Animators in both passes")
local fired = result.fired.take
check(math.abs(fired[5].t - 4.6154) < 1 / 30 + 1e-6 and fired[5].name == "Slash", "events land within one frame of their time (Slash on bar 2.5)")
check(#result.shots == 3 and #shots == 3 and shots[1].name == "Opening" and shots[2].name == "Clash" and math.abs(shots[2].t - 4.6154) < 1 / 30 + 1e-6, "3 shots, captured in the take only, on their bars")
check(shots[3].fov == 40 and near(shots[3].position, roblox.Vector3.new(10, 6, -10)), "the last shot sees the last camera key")
local rival = nil
for _, item in vfx do
	if item.name == "Dust" then
		rival = item.target
	end
end
check(rival and rival.Parent and near(rival.Parent:GetPivot().Position, roblox.Vector3.new(2, 0, 0)), "move: Rival walked to [2, 0, 0] over 0.6 s before Dust")
check(camera.CameraType == roblox.Enum.CameraType.Custom and camera.CameraSubject == "PlayerHumanoid" and near(camera.CFrame.Position, roblox.Vector3.new(1, 2, 3)) and camera.FieldOfView == 70, "reset: camera type, subject, position and field of view restored")
local leftovers = 0
for _, child in world.children do
	if not destroyed[child] then
		leftovers += 1
	end
end
local blackouts, folders = 0, 0
for _, item in created do
	if item.Name == "SceneRehearsal" then
		blackouts += 1
		leftovers += if destroyed[item] then 0 else 1
	elseif item.Name == "Scene_SwordClash" then
		folders += 1
		leftovers += if destroyed[item] then 0 else 1
	end
end
check(leftovers == 0 and blackouts == 1 and folders == 2 and #world.children == 0 and #playerGui.children == 0, "reset: both actor folders (rehearsal, take) and the black screen destroyed and unparented")

print("repeatable")
local first = table.clone(shots)
table.clear(shots)
run()
local same = #shots == #first
for i, shot in shots do
	same = same and near(shot.position, first[i].position, 1e-6) and shot.t == first[i].t
end
check(same, "a second run captures the same frames at the same times")

print("missing assets, no rehearsal, errors")
assets:FindFirstChild("Rival").Name = "RivalOld"
table.clear(shots)
result = run({ rehearse = false })
check(#result.missing == 1 and result.missing[1] == "ReplicatedStorage/SceneAssets/Rival" and #result.fired.take == 7, "a missing template is reported once (actor + preload) and the scene still plays")
check(#result.fired.rehearsal == 0 and #shots == 3, "rehearse = false: one pass")
assets:FindFirstChild("RivalOld").Name = "Rival"
result = run({ handlers = { vfx = function()
	error("effect blew up")
end } })
check(result.error and string.find(result.error, "effect blew up", 1, true) and camera.CameraType == roblox.Enum.CameraType.Custom, "an error mid-scene still resets the camera")

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
