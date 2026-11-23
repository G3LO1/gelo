-- Sfx.luau under Lune with Roblox's API database (real Sound instances) and the SfxIds module that
-- sfx_manifest.py generated from the example: random approved takes, pitch range, quieter repeats,
-- and the sync with animation markers: when AnimationSet fires Chop's "Hit" marker, the SwordHit
-- sound and the Slash Vfx play together at the weapon.
-- Usage (repo root): lune run tests/roblox-animation-vfx/sfx_test <generated SfxIds.luau>

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

local ASSETS = "plugins/roblox-studio/skills/roblox-animation-vfx/assets"
local game = roblox.Instance.new("DataModel")
local warnings = {}
local seed = 7
local Random = {
	new = function()
		local rng = {}
		local function next()
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		function rng.NextInteger(_, low, high)
			return low + math.floor(next() * (high - low + 1))
		end
		function rng.NextNumber(_, low, high)
			return low + next() * (high - low)
		end
		return rng
	end,
}
local env = {
	game = game,
	Instance = roblox.Instance,
	Enum = roblox.Enum,
	Random = Random,
	os = os,
	math = math,
	string = string,
	table = table,
	warn = function(message)
		table.insert(warnings, message)
	end,
}
local function load(path)
	return luau.load(fs.readFile(path), { debugName = path, environment = env })()
end

local Sfx = load(`{ASSETS}/Sfx.luau`)
local SfxIds = load(process.args[1])
check(#SfxIds.SwordHit.Ids == 1 and SfxIds.SwordHit.Ids[1] == "rbxassetid://1110001", "generated module: SwordHit has only its approved take")
check(#SfxIds.Footstep.Ids == 1 and #SfxIds.Pickup.Ids == 0 and #SfxIds.UiHover.Ids == 0, "picked, uploaded (in moderation) and generated takes stay out")
check(SfxIds.SwordHit.Marker == "Chop:Hit" and SfxIds.SwordHit.Vfx == "Slash" and SfxIds.UiHover.Spatial == false, "marker, vfx and spatial carried over")

local played = {}
local now = 0
Sfx.clock = function()
	return now
end
Sfx.random = Random.new()
Sfx.player = function(sound)
	table.insert(played, sound)
end
local vfxPlayed = {}
local Vfx = {
	play = function(name, target)
		table.insert(vfxPlayed, { name = name, target = target, sounds = #played })
	end,
}
-- two approved takes, to see the random pick and pitch
SfxIds.Footstep.Ids = { "rbxassetid://2220001", "rbxassetid://2220003" }
Sfx.configure(SfxIds, { vfx = Vfx })

local part = roblox.Instance.new("Part")
local ids, pitchOk = {}, true
for i = 1, 40 do
	now = i -- far apart: no repeat damping
	local sound = Sfx.play("Footstep", part)
	ids[sound.SoundId] = true
	pitchOk = pitchOk and sound.PlaybackSpeed >= 0.9 - 1e-6 and sound.PlaybackSpeed <= 1.1 + 1e-6
end
check(ids["rbxassetid://2220001"] and ids["rbxassetid://2220003"], "random take: both approved takes get played")
check(pitchOk and played[1].PlaybackSpeed ~= played[2].PlaybackSpeed, "pitch varies within the manifest range (0.9-1.1)")
check(played[1].Parent == part and played[1].RollOffMaxDistance == 80, "spatial sounds play from the part (3D)")
check(math.abs(played[1].Volume - 0.4) < 1e-6, "volume from the manifest")
now = 100
local first = Sfx.play("Footstep", part)
now = 100.05
local fast = Sfx.play("Footstep", part)
now = 100.5
local later = Sfx.play("Footstep", part)
check(math.abs(fast.Volume - 0.2) < 1e-6 and math.abs(first.Volume - 0.4) < 1e-6 and math.abs(later.Volume - 0.4) < 1e-6, "a repeat inside MinInterval plays at RepeatVolume, later ones at full volume")
local ui = { Ids = { "rbxassetid://9" }, Volume = 0.3, Pitch = { 1, 1 }, MinInterval = 0, RepeatVolume = 1, Spatial = false }
Sfx.Sounds.UiTest = ui
check(Sfx.play("UiTest", part).Parent == game:GetService("SoundService"), "non-spatial sounds (UI) play from SoundService")
check(Sfx.play("Pickup", part) == nil and Sfx.play("Pickup", part) == nil and #warnings == 1 and string.find(warnings[1], "no approved take", 1, true), "a sound with no approved take plays nothing and warns once")
check(Sfx.play("Nope") == nil and #warnings == 2, "unknown sound warns")

print("sync with animation markers (AnimationSet + Vfx)")
local AnimationSet = load(`{ASSETS}/AnimationSet.luau`)
local tracks = {}
local animator = {}
function animator:LoadAnimation(animation)
	local track = { Name = animation.Name, signals = {} }
	function track:GetMarkerReachedSignal(marker)
		local signal = { handlers = {} }
		function signal:Connect(fn)
			table.insert(self.handlers, fn)
			return { Disconnect = function() end }
		end
		self.signals[marker] = signal
		return signal
	end
	function track:Play() end
	function track:Stop() end
	function track:Destroy() end
	tracks[animation.Name] = track
	return track
end
local P = roblox.Enum.AnimationPriority
local set = AnimationSet.new(animator, {
	Chop = { Id = "rbxassetid://12", Priority = P.Action, Looped = false, Markers = { "Hit" } },
	Walk = { Id = "rbxassetid://11", Priority = P.Movement, Looped = true, Markers = { "Footstep" } },
})
Sfx.Sounds.UiTest = nil
local weapon = roblox.Instance.new("Part")
local connections = Sfx.bind(set, weapon)
check(#connections == 2, "bind(): SwordHit -> Chop:Hit and Footstep -> Walk:Footstep connected")
table.clear(played)
table.clear(vfxPlayed)
now = 200
tracks.Chop.signals.Hit.handlers[1]("")
check(#played == 1 and played[1].Name == "SwordHit" and played[1].Parent == weapon, "Hit marker: SwordHit plays at the weapon")
check(#vfxPlayed == 1 and vfxPlayed[1].name == "Slash" and vfxPlayed[1].target == weapon and vfxPlayed[1].sounds == 1, "same marker, same frame: Slash Vfx at the weapon right after the sound")
now = 201
tracks.Walk.signals.Footstep.handlers[1]("")
check(#played == 2 and played[2].Name == "Footstep" and vfxPlayed[2] and vfxPlayed[2].name == "Dust", "Footstep marker: footstep sound + Dust")

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
