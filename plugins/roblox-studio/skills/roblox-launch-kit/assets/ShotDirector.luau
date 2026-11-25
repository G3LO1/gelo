--!strict
-- ShotDirector: plays a scene from Scenes.luau (scene_spec.py) the same way every time, for test
-- captures (before/after a change), trailer takes and thumbnail shots.
--
--   1. actors: clones of the scene's templates, placed where the scene says (run it from a
--      LocalScript in a playtest: the clones exist only on your screen, so every take is identical)
--   2. ready: preloads the scene's assets and streams in the area around every camera key
--   3. rehearsal: the whole scene once behind a black screen, sounds muted, so every model, texture
--      and effect has been drawn once before the camera gets there
--   4. the take: camera path, events on their times, `onShot` called on every shot
--   5. reset: camera, clones, black screen back to how they were, even after an error
--
--   local result = ShotDirector.run(Scenes.SwordClash, {
--       modules = { Vfx = Vfx, Sfx = Sfx, Animations = Animations },
--       onShot = function(shot, t, camera) print("SHOT", shot.Name, t) end, -- Studio MCP: screen_capture here
--   })
-- Camera and events are pure functions of time (cameraAt, due), so the same scene gives the same
-- frames on every run: compare captures before and after a change, or cut takes on the beat.

local ShotDirector = {}

export type Options = {
	modules: { Vfx: any?, Sfx: any?, Animations: any? }?,
	handlers: { [string]: (event: any, actor: any, pass: string) -> () }?,
	onShot: ((shot: any, t: number, camera: any) -> ())?,
	rehearse: boolean?,
	-- engine stand-ins (tests, custom setups)
	step: (() -> number)?,
	root: any?,
	camera: any?,
	playerGui: any?,
	contentProvider: any?,
	workspace: any?,
	log: ((string) -> ())?,
}

local EASE = {
	Linear = function(a: number)
		return a
	end,
	Sine = function(a: number)
		return 0.5 - 0.5 * math.cos(math.pi * a)
	end,
	Quad = function(a: number)
		return if a < 0.5 then 2 * a * a else 1 - 2 * (1 - a) * (1 - a)
	end,
	Cubic = function(a: number)
		return if a < 0.5 then 4 * a * a * a else 1 - 4 * (1 - a) ^ 3
	end,
}

-- Camera CFrame and field of view at time t (holds the first/last key outside the path).
function ShotDirector.cameraAt(scene: any, t: number): (CFrame, number)
	local keys = scene.Camera
	local a, b = keys[1], keys[#keys]
	if t <= a.T then
		return CFrame.lookAt(a.Position, a.LookAt), a.Fov
	end
	if t >= b.T then
		return CFrame.lookAt(b.Position, b.LookAt), b.Fov
	end
	for i = 1, #keys - 1 do
		local k0, k1 = keys[i], keys[i + 1]
		if t >= k0.T and t <= k1.T then
			local span = k1.T - k0.T
			local alpha = if span > 0 then (EASE[k1.Ease] or EASE.Sine)((t - k0.T) / span) else 1
			local position = k0.Position:Lerp(k1.Position, alpha)
			local lookAt = k0.LookAt:Lerp(k1.LookAt, alpha)
			return CFrame.lookAt(position, lookAt), k0.Fov + (k1.Fov - k0.Fov) * alpha
		end
	end
	return CFrame.lookAt(b.Position, b.LookAt), b.Fov
end

-- Items whose time is in (t0, t1]; t0 < 0 also takes the ones at exactly 0.
function ShotDirector.due(items: { any }, t0: number, t1: number): { any }
	local out = {}
	for _, item in items do
		if item.T > t0 and item.T <= t1 then
			table.insert(out, item)
		end
	end
	return out
end

-- "ReplicatedStorage/SceneAssets/Hero" -> the instance, or nil.
function ShotDirector.resolve(root: any, path: string): any
	local node = root
	for part in string.gmatch(path, "[^/]+") do
		node = node and node:FindFirstChild(part)
	end
	return node
end

local function partOf(actor: any, name: string?): any
	if not actor then
		return nil
	end
	if name then
		local found = actor:FindFirstChild(name, true)
		if found then
			return found
		end
	end
	return actor.PrimaryPart or actor:FindFirstChildWhichIsA("BasePart", true)
end

local function face(position: Vector3, degrees: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, math.rad(degrees), 0)
end

function ShotDirector.run(scene: any, options: Options?)
	local opts = options or {}
	local modules = opts.modules or {}
	local log = opts.log or function(message: string)
		warn(`[ShotDirector] {message}`)
	end
	local root = opts.root or game
	local camera = opts.camera or workspace.CurrentCamera
	local world = opts.workspace or workspace
	local step = opts.step or function()
		return game:GetService("RunService").RenderStepped:Wait()
	end
	local rehearse = if opts.rehearse == nil then scene.Ready.Rehearse else opts.rehearse
	local result = { ready = true, missing = {}, fired = { rehearsal = {}, take = {} }, shots = {}, error = nil :: string? }

	-- templates and readiness
	local templates = {}
	for _, actor in scene.Actors do
		local template = ShotDirector.resolve(root, actor.From)
		if template then
			templates[actor.Name] = template
		else
			table.insert(result.missing, actor.From)
			log(`{scene.Name}: actor {actor.Name} template {actor.From} not found; the scene plays without it`)
		end
	end
	local preload = {}
	for _, path in scene.Ready.Preload do
		local found = ShotDirector.resolve(root, path)
		if found then
			table.insert(preload, found)
		elseif not table.find(result.missing, path) then
			table.insert(result.missing, path)
			log(`{scene.Name}: preload {path} not found`)
		end
	end
	local provider = opts.contentProvider or game:GetService("ContentProvider")
	local ok, err = pcall(function()
		provider:PreloadAsync(preload)
	end)
	if not ok then
		result.ready = false
		log(`{scene.Name}: preload failed ({err}); expect pop-in`)
	end
	if scene.Ready.StreamAround and world.StreamingEnabled then
		for _, key in scene.Camera do
			local streamed = pcall(function()
				world:RequestStreamAroundAsync(key.LookAt, scene.Ready.Timeout)
			end)
			result.ready = result.ready and streamed
		end
	end

	local saved = { CameraType = camera.CameraType, CameraSubject = camera.CameraSubject, CFrame = camera.CFrame, FieldOfView = camera.FieldOfView }
	local folder: any = nil
	local blackout: any = nil

	local function spawnActors(): { [string]: any }
		folder = Instance.new("Folder")
		folder.Name = `Scene_{scene.Name}`
		folder.Parent = world
		local actors = {}
		for _, actor in scene.Actors do
			local template = templates[actor.Name]
			if template then
				local clone = template:Clone()
				clone.Name = actor.Name
				clone:PivotTo(face(actor.Position, actor.Face))
				clone.Parent = folder
				actors[actor.Name] = clone
			end
		end
		return actors
	end

	local function fire(event: any, actors: { [string]: any }, moves: { any }, pass: string, t: number)
		if event.Kind == "sfx" and pass ~= "take" then
			return -- the rehearsal is silent
		end
		local actor = event.Actor and actors[event.Actor]
		local custom = opts.handlers and opts.handlers[event.Kind]
		if custom then
			custom(event, actor, pass)
		elseif event.Kind == "animation" then
			local animations = modules.Animations
			local humanoid = actor and actor:FindFirstChildWhichIsA("Humanoid", true)
			local controller = humanoid or (actor and actor:FindFirstChildWhichIsA("AnimationController", true))
			local animator = controller and controller:FindFirstChildWhichIsA("Animator")
			local specs = animations and (if animations.specsFor then animations.specsFor(humanoid) else animations.Specs)
			local spec = specs and specs[event.Name]
			if animator and spec then
				local animation = Instance.new("Animation")
				animation.AnimationId = spec.Id
				animator:LoadAnimation(animation):Play()
			elseif pass == "take" then
				log(`{scene.Name}: can't play animation {event.Name} on {event.Actor} (Animator or Animations spec missing)`)
			end
		elseif event.Kind == "vfx" then
			if modules.Vfx then
				modules.Vfx.play(event.Name, partOf(actor, event.Part) or (actor and actor:GetPivot().Position))
			end
		elseif event.Kind == "sfx" then
			if modules.Sfx then
				modules.Sfx.play(event.Name, partOf(actor, event.Part))
			end
		elseif event.Kind == "move" then
			if actor then
				local from = actor:GetPivot()
				local target = CFrame.new(event.To) * from.Rotation
				if (event.Time or 0) <= 0 then
					actor:PivotTo(target)
				else
					table.insert(moves, { actor = actor, from = from, to = target, start = t, time = event.Time })
				end
			end
		elseif event.Kind == "visible" then
			if actor then
				for _, part in actor:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = if event.Value then 0 else 1
					end
				end
			end
		else
			log(`{scene.Name}: no handler for event kind {event.Kind}`)
		end
		table.insert(result.fired[pass], { t = t, kind = event.Kind, name = event.Name, actor = event.Actor })
	end

	local function play(pass: string)
		local actors = spawnActors()
		local moves = {}
		local t = 0
		local function frame(t0: number, t1: number)
			local cf, fov = ShotDirector.cameraAt(scene, t1)
			camera.CFrame = cf
			camera.FieldOfView = fov
			for _, move in moves do
				local alpha = math.clamp((t1 - move.start) / move.time, 0, 1)
				move.actor:PivotTo(move.from:Lerp(move.to, alpha))
			end
			for _, event in ShotDirector.due(scene.Events, t0, t1) do
				fire(event, actors, moves, pass, t1)
			end
			if pass == "take" then
				for _, shot in ShotDirector.due(scene.Shots, t0, t1) do
					table.insert(result.shots, { name = shot.Name, use = shot.Use, t = t1, cframe = camera.CFrame })
					if opts.onShot then
						opts.onShot(shot, t1, camera)
					end
				end
			end
		end
		frame(-1, 0)
		while t < scene.Length - 1e-6 do
			local t1 = math.min(t + step(), scene.Length)
			frame(t, t1)
			t = t1
		end
		folder:Destroy()
		folder = nil
	end

	camera.CameraType = Enum.CameraType.Scriptable
	local ran, failure = pcall(function()
		if rehearse then
			blackout = Instance.new("ScreenGui")
			blackout.Name = "SceneRehearsal"
			blackout.IgnoreGuiInset = true
			blackout.DisplayOrder = 1000000
			local frame = Instance.new("Frame")
			frame.Size = UDim2.fromScale(1, 1)
			frame.BackgroundColor3 = Color3.new(0, 0, 0)
			frame.BorderSizePixel = 0
			frame.Parent = blackout
			blackout.Parent = opts.playerGui or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
			play("rehearsal")
			blackout:Destroy()
			blackout = nil
		end
		play("take")
	end)
	-- reset, whatever happened
	if folder then
		folder:Destroy()
	end
	if blackout then
		blackout:Destroy()
	end
	camera.CameraType = saved.CameraType
	camera.CameraSubject = saved.CameraSubject
	camera.CFrame = saved.CFrame
	camera.FieldOfView = saved.FieldOfView
	if not ran then
		result.error = tostring(failure)
		log(`{scene.Name}: stopped: {failure}`)
	end
	return result
end

return ShotDirector
