--!strict
-- Vfx: data-driven effects for feedback moments (hits, pickups, level ups, purchases, heals,
-- dust, explosions), looping glows/ambience and trails, built from presets with a
-- per-player quality level and a reduced-flashing option.
--
-- Put it in ReplicatedStorage (Rojo: src/shared/Vfx.luau) and play effects on the CLIENT:
-- the server fires a remote with the effect name and position, each client calls Vfx.play.
-- Effects never replicate, never yield, and clean themselves up.
--
--   Vfx.play("HitSpark", hitPosition)                       -- one-shot burst at a point
--   Vfx.play("LevelUp", character.HumanoidRootPart)        -- one-shot on a part / attachment
--   local glow = Vfx.attach("RarityGlow", toolHandle, { color = Vfx.Rarity.Epic })
--   glow:Stop()                                            -- loops: stop fades them out
--   Vfx.setQuality(0.5)  Vfx.setReducedFlashing(true)       -- from the settings menu
--
-- Textures: upload the PNGs from the skill's assets/textures/ (or your own) and paste the ids
-- into Vfx.Textures. Until then everything uses the engine's default sparkle texture.

local Vfx = {}

Vfx.Textures = {
	Glow = "rbxassetid://0", -- TODO: upload glow.png
	Star = "rbxassetid://0", -- TODO: upload star.png
	Spark = "rbxassetid://0", -- TODO: upload spark.png
	Smoke = "rbxassetid://0", -- TODO: upload smoke.png
	Ring = "rbxassetid://0", -- TODO: upload ring.png
}
local DEFAULT_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

Vfx.Rarity = {
	Common = Color3.fromRGB(200, 200, 200),
	Rare = Color3.fromRGB(70, 150, 255),
	Epic = Color3.fromRGB(170, 80, 255),
	Legendary = Color3.fromRGB(255, 190, 40),
}

-- Mobile caps emitters at 100 particles/s; keep looping rates well under it.
Vfx.MaxLoopRate = 60
Vfx.MaxBurst = 60

type Emitter = {
	texture: string,
	burst: number?, -- one-shot: particles emitted once
	rate: number?, -- loop: particles per second
	lifetime: { number },
	speed: { number },
	size: { { number } }, -- NumberSequence keypoints {time, value}
	transparency: { { number } },
	color: { Color3 }?, -- one color, or a gradient start -> end
	spread: number?,
	drag: number?,
	acceleration: Vector3?,
	lightEmission: number?,
	rotSpeed: { number }?,
	shape: string?, -- "Sphere" | "Box" | "Disc" | "Cylinder"
	emissionDirection: string?,
	squash: { { number } }?,
	zOffset: number?,
	lockedToPart: boolean?,
	flash: boolean?, -- bright flash: removed with reduced flashing
}

type Preset = {
	kind: "oneshot" | "loop",
	duration: number?, -- one-shots: seconds until cleanup
	emitters: { Emitter },
	light: { color: Color3, brightness: number, range: number, time: number }?,
	trail: { color: { Color3 }, lifetime: number, width: { { number } } }?,
}

local function gold(): { Color3 }
	return { Color3.fromRGB(255, 235, 140), Color3.fromRGB(255, 170, 30) }
end

Vfx.Presets = {
	HitSpark = {
		kind = "oneshot",
		duration = 0.6,
		emitters = {
			{
				texture = "Spark",
				burst = 14,
				lifetime = { 0.12, 0.25 },
				speed = { 18, 32 },
				spread = 180,
				drag = 6,
				size = { { 0, 0.35 }, { 1, 0 } },
				transparency = { { 0, 0 }, { 1, 1 } },
				color = { Color3.fromRGB(255, 240, 200) },
				lightEmission = 1,
				squash = { { 0, 1.5 }, { 1, 0.5 } },
			},
			{
				texture = "Glow",
				burst = 1,
				lifetime = { 0.1, 0.1 },
				speed = { 0, 0 },
				size = { { 0, 2.5 }, { 1, 0.5 } },
				transparency = { { 0, 0.2 }, { 1, 1 } },
				color = { Color3.fromRGB(255, 220, 160) },
				lightEmission = 1,
				flash = true,
			},
		},
	},
	Pickup = {
		kind = "oneshot",
		duration = 1.2,
		emitters = {
			{
				texture = "Star",
				burst = 10,
				lifetime = { 0.5, 0.9 },
				speed = { 4, 9 },
				spread = 180,
				drag = 3,
				acceleration = Vector3.new(0, 6, 0),
				size = { { 0, 0.5 }, { 1, 0 } },
				transparency = { { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } },
				color = gold(),
				lightEmission = 0.6,
				rotSpeed = { -180, 180 },
			},
			{
				texture = "Ring",
				burst = 1,
				lifetime = { 0.35, 0.35 },
				speed = { 0, 0 },
				size = { { 0, 0.5 }, { 1, 4 } },
				transparency = { { 0, 0.1 }, { 1, 1 } },
				color = { Color3.fromRGB(255, 230, 120) },
				lightEmission = 1,
			},
		},
	},
	LevelUp = {
		kind = "oneshot",
		duration = 2,
		emitters = {
			{
				texture = "Star",
				burst = 30,
				lifetime = { 0.8, 1.4 },
				speed = { 6, 14 },
				spread = 25,
				emissionDirection = "Top",
				drag = 1.5,
				size = { { 0, 0.6 }, { 1, 0.1 } },
				transparency = { { 0, 0 }, { 0.8, 0.3 }, { 1, 1 } },
				color = gold(),
				lightEmission = 0.8,
				rotSpeed = { -120, 120 },
			},
			{
				texture = "Ring",
				burst = 2,
				lifetime = { 0.6, 0.8 },
				speed = { 0, 0 },
				size = { { 0, 1 }, { 1, 9 } },
				transparency = { { 0, 0.2 }, { 1, 1 } },
				color = gold(),
				lightEmission = 1,
				zOffset = -1,
			},
		},
		light = { color = Color3.fromRGB(255, 220, 120), brightness = 4, range = 14, time = 0.6 },
	},
	Purchase = {
		kind = "oneshot",
		duration = 1.6,
		emitters = {
			{
				texture = "Star",
				burst = 24,
				lifetime = { 0.6, 1.1 },
				speed = { 8, 16 },
				spread = 180,
				drag = 2,
				acceleration = Vector3.new(0, -12, 0),
				size = { { 0, 0.5 }, { 1, 0.15 } },
				transparency = { { 0, 0 }, { 1, 1 } },
				color = { Color3.fromRGB(120, 255, 160), Color3.fromRGB(40, 200, 255) },
				lightEmission = 0.7,
				rotSpeed = { -200, 200 },
			},
			{
				texture = "Glow",
				burst = 1,
				lifetime = { 0.25, 0.25 },
				speed = { 0, 0 },
				size = { { 0, 1 }, { 1, 5 } },
				transparency = { { 0, 0.3 }, { 1, 1 } },
				color = { Color3.fromRGB(160, 255, 200) },
				lightEmission = 1,
				flash = true,
			},
		},
	},
	Heal = {
		kind = "oneshot",
		duration = 1.6,
		emitters = {
			{
				texture = "Glow",
				burst = 16,
				lifetime = { 0.8, 1.2 },
				speed = { 1, 3 },
				shape = "Cylinder",
				emissionDirection = "Top",
				acceleration = Vector3.new(0, 4, 0),
				size = { { 0, 0.4 }, { 0.5, 0.6 }, { 1, 0 } },
				transparency = { { 0, 0.2 }, { 1, 1 } },
				color = { Color3.fromRGB(120, 255, 140) },
				lightEmission = 0.8,
			},
		},
	},
	Dust = {
		kind = "oneshot",
		duration = 1.2,
		emitters = {
			{
				texture = "Smoke",
				burst = 6,
				lifetime = { 0.5, 0.9 },
				speed = { 2, 5 },
				spread = 70,
				emissionDirection = "Top",
				drag = 4,
				size = { { 0, 0.8 }, { 1, 2.2 } },
				transparency = { { 0, 0.5 }, { 1, 1 } },
				color = { Color3.fromRGB(190, 175, 150) },
				lightEmission = 0,
				rotSpeed = { -40, 40 },
			},
		},
	},
	Explosion = {
		kind = "oneshot",
		duration = 2.5,
		emitters = {
			{
				texture = "Glow",
				burst = 1,
				lifetime = { 0.15, 0.15 },
				speed = { 0, 0 },
				size = { { 0, 4 }, { 1, 10 } },
				transparency = { { 0, 0 }, { 1, 1 } },
				color = { Color3.fromRGB(255, 230, 170) },
				lightEmission = 1,
				flash = true,
			},
			{
				texture = "Smoke",
				burst = 18,
				lifetime = { 0.9, 1.6 },
				speed = { 6, 14 },
				spread = 180,
				drag = 3,
				acceleration = Vector3.new(0, 3, 0),
				size = { { 0, 2 }, { 1, 6 } },
				transparency = { { 0, 0.2 }, { 1, 1 } },
				color = { Color3.fromRGB(255, 150, 50), Color3.fromRGB(60, 55, 55) },
				lightEmission = 0.2,
				rotSpeed = { -60, 60 },
			},
			{
				texture = "Spark",
				burst = 20,
				lifetime = { 0.4, 0.8 },
				speed = { 25, 45 },
				spread = 180,
				drag = 2,
				acceleration = Vector3.new(0, -30, 0),
				size = { { 0, 0.4 }, { 1, 0 } },
				transparency = { { 0, 0 }, { 1, 1 } },
				color = { Color3.fromRGB(255, 200, 100) },
				lightEmission = 1,
			},
		},
		light = { color = Color3.fromRGB(255, 170, 80), brightness = 6, range = 20, time = 0.4 },
	},
	RarityGlow = {
		kind = "loop",
		emitters = {
			{
				texture = "Glow",
				rate = 6,
				lifetime = { 0.8, 1.2 },
				speed = { 0.5, 1.5 },
				shape = "Sphere",
				size = { { 0, 0.3 }, { 0.5, 0.6 }, { 1, 0 } },
				transparency = { { 0, 0.4 }, { 1, 1 } },
				color = { Vfx.Rarity.Epic },
				lightEmission = 1,
				lockedToPart = true,
			},
			{
				texture = "Star",
				rate = 3,
				lifetime = { 0.6, 1 },
				speed = { 1, 2 },
				shape = "Sphere",
				acceleration = Vector3.new(0, 1.5, 0),
				size = { { 0, 0.25 }, { 1, 0 } },
				transparency = { { 0, 0 }, { 1, 1 } },
				color = { Vfx.Rarity.Epic },
				lightEmission = 1,
				rotSpeed = { -90, 90 },
			},
		},
	},
	Fireflies = {
		kind = "loop",
		emitters = {
			{
				texture = "Glow",
				rate = 4,
				lifetime = { 4, 7 },
				speed = { 0.3, 1 },
				shape = "Box",
				spread = 180,
				drag = 0.5,
				size = { { 0, 0 }, { 0.2, 0.25 }, { 0.8, 0.25 }, { 1, 0 } },
				transparency = { { 0, 0.1 }, { 1, 0.6 } },
				color = { Color3.fromRGB(220, 255, 120) },
				lightEmission = 1,
			},
		},
	},
	SpeedTrail = {
		kind = "loop",
		emitters = {},
		trail = {
			color = { Color3.fromRGB(150, 220, 255), Color3.fromRGB(255, 255, 255) },
			lifetime = 0.25,
			width = { { 0, 1 }, { 1, 0 } },
		},
	},
} :: { [string]: Preset }

local state = { quality = 1, reducedFlashing = false }

function Vfx.setQuality(quality: number)
	state.quality = math.clamp(quality, 0, 1)
end

function Vfx.setReducedFlashing(enabled: boolean)
	state.reducedFlashing = enabled
end

local function sequence(points: { { number } }): NumberSequence
	local keypoints = {}
	for _, point in points do
		table.insert(keypoints, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keypoints)
end

local function colorSequence(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	return ColorSequence.new(colors[1], colors[#colors])
end

local function texture(name: string): string
	local id = Vfx.Textures[name]
	if id == nil or id == "rbxassetid://0" or id == "" then
		return DEFAULT_TEXTURE
	end
	return id
end

-- Scaled particle count for the current quality (never below 1 for a visible effect).
function Vfx.scaled(count: number, quality: number?): number
	local q = quality or state.quality
	if q <= 0 then
		return 0
	end
	return math.max(1, math.floor(count * (0.35 + 0.65 * q) + 0.5))
end

export type Options = { color: Color3?, scale: number?, quality: number?, reducedFlashing: boolean? }

-- Builds the effect's instances under a new Attachment (not parented). Pure: no Emit, no
-- timers, safe to call anywhere (tests run it outside Roblox).
function Vfx.build(name: string, options: Options?): (Attachment, Preset)
	local preset = Vfx.Presets[name]
	assert(preset, `Vfx: unknown effect "{name}"`)
	local opts: Options = options or ({} :: Options)
	local quality = opts.quality or state.quality
	local reduced = if opts.reducedFlashing == nil then state.reducedFlashing else opts.reducedFlashing
	local scale = opts.scale or 1

	local attachment = Instance.new("Attachment")
	attachment.Name = `Vfx_{name}`
	for index, spec in preset.emitters do
		if spec.flash and reduced then
			continue
		end
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = `{name}{index}`
		emitter.Texture = texture(spec.texture)
		emitter.Enabled = preset.kind == "loop"
		emitter.Rate = if spec.rate then math.min(Vfx.scaled(spec.rate, quality), Vfx.MaxLoopRate) else 0
		emitter.Lifetime = NumberRange.new(spec.lifetime[1], spec.lifetime[2])
		emitter.Speed = NumberRange.new(spec.speed[1] * scale, spec.speed[2] * scale)
		local sizePoints = {}
		for _, point in spec.size do
			table.insert(sizePoints, { point[1], point[2] * scale })
		end
		emitter.Size = sequence(sizePoints)
		emitter.Transparency = sequence(spec.transparency)
		local colors = spec.color or { Color3.new(1, 1, 1) }
		if opts.color then
			colors = { opts.color }
		end
		emitter.Color = colorSequence(colors)
		emitter.LightEmission = spec.lightEmission or 0
		emitter.LightInfluence = if (spec.lightEmission or 0) > 0 then 0 else 1
		emitter.Drag = spec.drag or 0
		emitter.Acceleration = (spec.acceleration or Vector3.zero) * scale
		local spread = spec.spread or 0
		emitter.SpreadAngle = Vector2.new(spread, spread)
		if spec.rotSpeed then
			emitter.RotSpeed = NumberRange.new(spec.rotSpeed[1], spec.rotSpeed[2])
			emitter.Rotation = NumberRange.new(0, 360)
		end
		if spec.shape then
			emitter.Shape = (Enum.ParticleEmitterShape :: any)[spec.shape]
		end
		if spec.emissionDirection then
			emitter.EmissionDirection = (Enum.NormalId :: any)[spec.emissionDirection]
		end
		if spec.squash then
			emitter.Squash = sequence(spec.squash)
		end
		emitter.ZOffset = spec.zOffset or 0
		emitter.LockedToPart = spec.lockedToPart == true
		emitter:SetAttribute("Burst", if spec.burst then math.min(Vfx.scaled(spec.burst, quality), Vfx.MaxBurst) else 0)
		emitter.Parent = attachment
	end
	if preset.light and not reduced and quality > 0.3 then
		local light = Instance.new("PointLight")
		light.Name = "Flash"
		light.Color = preset.light.color
		light.Brightness = preset.light.brightness
		light.Range = preset.light.range * scale
		light.Shadows = false
		light:SetAttribute("FadeTime", preset.light.time)
		light.Parent = attachment
	end
	if preset.trail then
		local start = Instance.new("Attachment")
		start.Name = "TrailStart"
		start.Position = Vector3.new(0, 0.5 * scale, 0)
		start.Parent = attachment
		local finish = Instance.new("Attachment")
		finish.Name = "TrailEnd"
		finish.Position = Vector3.new(0, -0.5 * scale, 0)
		finish.Parent = attachment
		local trail = Instance.new("Trail")
		trail.Attachment0 = start
		trail.Attachment1 = finish
		trail.Lifetime = preset.trail.lifetime
		trail.Color = colorSequence(if opts.color then { opts.color } else preset.trail.color)
		trail.WidthScale = sequence(preset.trail.width)
		trail.Transparency = sequence({ { 0, 0.3 }, { 1, 1 } })
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Parent = attachment
	end
	return attachment, preset
end

-- Puts an effect's attachment at a point (under Terrain), on a part, or where an attachment is.
-- Attachments only work directly under a BasePart (or Terrain), never under another attachment.
local function place(attachment: Attachment, target: Instance | Vector3)
	if typeof(target) == "Vector3" then
		attachment.Parent = workspace.Terrain
		attachment.WorldPosition = target
	elseif (target :: Instance):IsA("Attachment") then
		local at = target :: Attachment
		attachment.Parent = at.Parent
		attachment.WorldCFrame = at.WorldCFrame
	else
		attachment.Parent = target :: Instance
	end
	-- Trail end points must sit under the same part as the effect.
	for _, child in attachment:GetChildren() do
		if child:IsA("Attachment") then
			local offset = child.Position
			child.Parent = attachment.Parent
			child.CFrame = attachment.CFrame * CFrame.new(offset)
		end
	end
end

local function cleanup(attachment: Attachment)
	for _, child in attachment:GetDescendants() do
		if child:IsA("Trail") then
			if child.Attachment0 then
				child.Attachment0:Destroy()
			end
			if child.Attachment1 then
				child.Attachment1:Destroy()
			end
		end
	end
	attachment:Destroy()
end

-- One-shot effect at a position, part or attachment. Returns the attachment (already
-- scheduled for cleanup), or nil when quality is 0.
function Vfx.play(name: string, target: Instance | Vector3, options: Options?): Attachment?
	if state.quality <= 0 and not (options and options.quality) then
		return nil
	end
	local attachment, preset = Vfx.build(name, options)
	place(attachment, target)
	for _, child in attachment:GetChildren() do
		if child:IsA("ParticleEmitter") then
			local burst = child:GetAttribute("Burst") :: number
			if burst > 0 then
				child:Emit(burst)
			end
		elseif child:IsA("PointLight") then
			local fade = child:GetAttribute("FadeTime") :: number
			game:GetService("TweenService"):Create(child, TweenInfo.new(fade), { Brightness = 0 }):Play()
		end
	end
	task.delay(preset.duration or 2, cleanup, attachment)
	return attachment
end

export type Handle = { Instance: Attachment, Stop: (self: Handle, fade: number?) -> () }

-- Looping effect attached to a part or attachment until Stop() is called.
function Vfx.attach(name: string, target: Instance, options: Options?): Handle
	local attachment = Vfx.build(name, options)
	place(attachment, target)
	local handle = { Instance = attachment }
	function handle.Stop(_self: Handle, fade: number?)
		local longest = 0
		for _, child in attachment:GetDescendants() do
			if child:IsA("ParticleEmitter") then
				child.Enabled = false
				longest = math.max(longest, child.Lifetime.Max)
			elseif child:IsA("Trail") then
				child.Enabled = false
				longest = math.max(longest, child.Lifetime)
			end
		end
		task.delay(fade or longest, cleanup, attachment)
	end
	return handle :: Handle
end

return Vfx
