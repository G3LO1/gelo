--!strict
-- Sfx: plays the game's sound effects from the generated SfxIds module (sfx_manifest.py luau):
-- a random approved take and a slightly different pitch every time (a hundred hits don't sound
-- like a machine gun), quieter when the same sound repeats faster than its MinInterval (a whole
-- horde still sounds clean), and bound to animation markers together with their Vfx preset, so
-- the pose, the effect and the sound land on the same frame.
--
-- Client code, next to Vfx and AnimationSet (ReplicatedStorage):
--   Sfx.configure(require(Shared.SfxIds), { vfx = Vfx })
--   local set = AnimationSet.new(animator, Animations.specsFor(humanoid))
--   Sfx.bind(set, character.HumanoidRootPart)   -- every sound with Marker = "Chop:Hit" etc.
--   Sfx.play("Pickup", coinPart)                 -- code-triggered moments (Event = ...)
-- Sounds with Spatial = true play from the part (3D); others play from SoundService (UI, 2D).

local Sfx = {}

export type Spec = {
	Ids: { string },
	Volume: number,
	Pitch: { number },
	MinInterval: number,
	RepeatVolume: number,
	Marker: string?,
	Event: string?,
	Vfx: string?,
	Spatial: boolean?,
}

Sfx.Sounds = {} :: { [string]: Spec }
Sfx.Vfx = nil :: any
-- Replaceable for tests and for custom mixing (SoundGroups, ducking):
Sfx.clock = os.clock
Sfx.random = Random.new()
Sfx.player = function(sound: Sound)
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

local lastPlayed: { [string]: number } = {}
local warned: { [string]: boolean } = {}

function Sfx.configure(sounds: { [string]: Spec }, options: { vfx: any? }?)
	Sfx.Sounds = sounds
	Sfx.Vfx = options and options.vfx
	table.clear(lastPlayed)
end

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn(`[Sfx] {message}`)
	end
end

-- Plays one take. Returns the Sound, or nil when the sound has no approved take yet.
function Sfx.play(name: string, target: Instance?, options: { volume: number? }?): Sound?
	local spec = Sfx.Sounds[name]
	if not spec then
		warnOnce(name, `unknown sound "{name}"`)
		return nil
	end
	if #spec.Ids == 0 then
		warnOnce(name, `{name} has no approved take yet (upload it and wait for moderation)`)
		return nil
	end
	local now = Sfx.clock()
	local volume = spec.Volume * (options and options.volume or 1)
	local last = lastPlayed[name]
	if last and now - last < spec.MinInterval then
		volume *= spec.RepeatVolume
	end
	lastPlayed[name] = now
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = spec.Ids[Sfx.random:NextInteger(1, #spec.Ids)]
	sound.Volume = volume
	sound.PlaybackSpeed = Sfx.random:NextNumber(spec.Pitch[1], spec.Pitch[2])
	if spec.Spatial ~= false and target and target:IsA("BasePart") then
		sound.RollOffMinDistance = 5
		sound.RollOffMaxDistance = 80
		sound.Parent = target
	else
		sound.Parent = game:GetService("SoundService")
	end
	Sfx.player(sound)
	return sound
end

-- Connects every sound whose Marker is "<Animation>:<Marker>" to that marker on an AnimationSet:
-- when the marker fires, the sound and its Vfx preset play at `target`. Returns the connections.
function Sfx.bind(set: any, target: Instance): { any }
	local connections = {}
	local names = {}
	for name in Sfx.Sounds do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local spec = Sfx.Sounds[name]
		local animation, marker = string.match(spec.Marker or "", "^([%w_]+):([%w_]+)$")
		if animation and marker then
			local connection = set:onMarker(animation, marker, function()
				Sfx.play(name, target)
				if spec.Vfx and Sfx.Vfx then
					Sfx.Vfx.play(spec.Vfx, target)
				end
			end)
			if connection then
				table.insert(connections, connection)
			end
		end
	end
	return connections
end

return Sfx
