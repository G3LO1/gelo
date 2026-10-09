--!strict
-- AnimationSet: loads a character's animations once from the generated Animations.Specs and
-- plays them by name, with marker callbacks and Animation Graph parameters.
--
--   local Animations = require(ReplicatedStorage.Shared.Animations)
--   local set = AnimationSet.new(humanoid:WaitForChild("Animator"), Animations.Specs)
--   set:onMarker("Chop", "Hit", function() Net.fire("ChopHit") end)
--   set:play("Chop")
--   set:setParameter("Locomotion", "Speed", rootPart.AssemblyLinearVelocity.Magnitude)
--   humanoid.Died:Once(function() set:destroy() end)
--
-- Play the local player's animations on the client (they replicate to others). For NPCs: a
-- few can animate from the server; many NPCs should animate on clients.
-- Specs with Id "rbxassetid://0" (not uploaded yet) are skipped with one warning, so the game
-- keeps running while animations are being made.

local AnimationSet = {}
AnimationSet.__index = AnimationSet

export type Spec = {
	Id: string,
	Priority: Enum.AnimationPriority?,
	Looped: boolean?,
	Markers: { string }?,
	Graph: boolean?,
	Parameters: { string }?,
}

export type PlayOptions = { fade: number?, weight: number?, speed: number? }

type Self = {
	tracks: { [string]: AnimationTrack },
	connections: { RBXScriptConnection },
	specs: { [string]: Spec },
}

export type AnimationSet = typeof(setmetatable({} :: Self, AnimationSet))

function AnimationSet.new(animator: Animator, specs: { [string]: Spec }): AnimationSet
	local self = setmetatable({ tracks = {}, connections = {}, specs = specs }, AnimationSet)
	local missing = {}
	for name, spec in specs do
		if spec.Id == "rbxassetid://0" or spec.Id == "" then
			table.insert(missing, name)
			continue
		end
		local animation = Instance.new("Animation")
		animation.Name = name
		animation.AnimationId = spec.Id
		local track = animator:LoadAnimation(animation)
		if not spec.Graph then
			track.Priority = spec.Priority or Enum.AnimationPriority.Action
			track.Looped = spec.Looped == true
		end
		self.tracks[name] = track
	end
	if #missing > 0 then
		table.sort(missing)
		warn(`AnimationSet: no asset id yet for {table.concat(missing, ", ")}`)
	end
	return self
end

function AnimationSet.play(self: AnimationSet, name: string, options: PlayOptions?): AnimationTrack?
	local track = self.tracks[name]
	if not track then
		return nil
	end
	local opts: PlayOptions = options or ({} :: PlayOptions)
	track:Play(opts.fade or 0.1, opts.weight or 1, opts.speed or 1)
	return track
end

function AnimationSet.stop(self: AnimationSet, name: string, fade: number?)
	local track = self.tracks[name]
	if track and track.IsPlaying then
		track:Stop(fade or 0.1)
	end
end

function AnimationSet.isPlaying(self: AnimationSet, name: string): boolean
	local track: AnimationTrack? = self.tracks[name]
	if track then
		return track.IsPlaying
	end
	return false
end

-- Calls callback(param) every time the animation reaches the marker. Markers come from the
-- Animation Editor's event track; the manifest lists which ones each animation has.
function AnimationSet.onMarker(
	self: AnimationSet,
	name: string,
	marker: string,
	callback: (param: string) -> ()
): RBXScriptConnection?
	local track = self.tracks[name]
	if not track then
		return nil
	end
	local spec = self.specs[name]
	if spec.Markers and not table.find(spec.Markers, marker) then
		warn(`AnimationSet: {name} has no marker "{marker}" in the manifest`)
	end
	local connection = track:GetMarkerReachedSignal(marker):Connect(callback)
	table.insert(self.connections, connection)
	return connection
end

-- Animation Graph assets: drive their parameters (speed, grounded, aim...) from gameplay code.
function AnimationSet.setParameter(self: AnimationSet, name: string, parameter: string, value: any)
	local track = self.tracks[name]
	if track then
		(track :: any):SetParameter(parameter, value)
	end
end

function AnimationSet.stopAll(self: AnimationSet, fade: number?)
	for _, track in self.tracks do
		if track.IsPlaying then
			track:Stop(fade or 0.1)
		end
	end
end

function AnimationSet.destroy(self: AnimationSet)
	self:stopAll(0)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	for _, track in self.tracks do
		track:Destroy()
	end
	table.clear(self.tracks)
end

return AnimationSet
