-- Vfx.luau presets and AnimationSet.luau behaviour, run under Lune with Roblox's real API
-- database (invalid property names, types and enums throw).
-- Usage (repo root): lune run tests/roblox-animation-vfx/vfx_test [generated Animations.luau]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local ASSETS = "plugins/roblox-studio/skills/roblox-animation-vfx/assets"
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

local warnings = {}
local env = {
	Instance = roblox.Instance,
	Enum = roblox.Enum,
	Color3 = roblox.Color3,
	Vector2 = roblox.Vector2,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	warn = function(message)
		table.insert(warnings, message)
	end,
}
local function load(path)
	return luau.load(fs.readFile(path), { debugName = path, environment = env })()
end

print("Vfx presets")
local Vfx = load(`{ASSETS}/Vfx.luau`)
local names = {}
for name in Vfx.Presets do
	table.insert(names, name)
end
table.sort(names)
check(#names >= 10, `{#names} presets`)

local function emitters(attachment)
	local list = {}
	for _, child in attachment:GetChildren() do
		if child:IsA("ParticleEmitter") then
			table.insert(list, child)
		end
	end
	return list
end

local allValid, budgets, flashesRemoved, scaledDown = true, true, true, true
for _, name in names do
	local ok, full = pcall(Vfx.build, name, { quality = 1 })
	if not ok then
		allValid = false
		print(`    {name}: {full}`)
		continue
	end
	local preset = Vfx.Presets[name]
	for _, e in emitters(full) do
		local burst = e:GetAttribute("Burst")
		if e.Rate > 100 or e.Rate > Vfx.MaxLoopRate or burst > Vfx.MaxBurst or e.Lifetime.Max > 20 then
			budgets = false
			print(`    {name}/{e.Name}: Rate {e.Rate}, Burst {burst}, Lifetime {e.Lifetime.Max}`)
		end
		if preset.kind == "oneshot" and (e.Enabled or burst < 1) then
			budgets = false
			print(`    {name}/{e.Name}: one-shot emitters must be disabled with a burst`)
		end
		if preset.kind == "loop" and (not e.Enabled or e.Rate < 1) then
			budgets = false
			print(`    {name}/{e.Name}: loop emitters must be enabled with a rate`)
		end
		if e.LightEmission > 0 and e.LightInfluence ~= 0 then
			budgets = false
			print(`    {name}/{e.Name}: glowing particles should ignore scene lighting`)
		end
	end
	local reduced = Vfx.build(name, { quality = 1, reducedFlashing = true })
	for _, child in reduced:GetChildren() do
		if child:IsA("PointLight") then
			flashesRemoved = false
		end
	end
	for index, spec in preset.emitters do
		if spec.flash and reduced:FindFirstChild(`{name}{index}`) then
			flashesRemoved = false
		end
	end
	local low = Vfx.build(name, { quality = 0.3 })
	for _, e in emitters(low) do
		local fullEmitter = full:FindFirstChild(e.Name)
		local before = fullEmitter:GetAttribute("Burst") + fullEmitter.Rate
		local after = e:GetAttribute("Burst") + e.Rate
		if before > 3 and after >= before then
			scaledDown = false
			print(`    {name}/{e.Name}: quality 0.3 did not reduce {before} -> {after}`)
		end
	end
end
check(allValid, "every preset builds with valid Roblox properties")
check(budgets, "loops <= MaxLoopRate (mobile cap 100/s), bursts <= MaxBurst, lifetimes <= 20 s, glows unlit")
check(flashesRemoved, "reduced flashing removes flash emitters and lights")
check(scaledDown, "low quality emits fewer particles")
local tinted = Vfx.build("RarityGlow", { color = Vfx.Rarity.Legendary })
check(emitters(tinted)[1].Color.Keypoints[1].Value == Vfx.Rarity.Legendary, "color option tints the effect")
local trail = Vfx.build("SpeedTrail")
local t = trail:FindFirstChildOfClass("Trail")
check(t ~= nil and t.Attachment0 ~= nil and t.Attachment1 ~= nil, "trail preset wires two attachments")
check(emitters(Vfx.build("HitSpark"))[1].Texture == "rbxasset://textures/particles/sparkles_main.dds", "unset texture ids fall back to the engine sparkle")
Vfx.Textures.Spark = "rbxassetid://123"
check(emitters(Vfx.build("HitSpark"))[1].Texture == "rbxassetid://123", "uploaded texture ids are used")
check(Vfx.scaled(10, 0) == 0 and Vfx.scaled(10, 1) == 10 and Vfx.scaled(1, 0.1) == 1, "Vfx.scaled keeps visible effects visible")

print("Layered flipbooks")
local Layout, Mode = roblox.Enum.ParticleFlipbookLayout, roblox.Enum.ParticleFlipbookMode
local function byLayer(attachment, preset)
	local layers = {}
	for index, spec in Vfx.Presets[preset].emitters do
		local e = attachment:FindFirstChild(`{preset}{index}`)
		if e and spec.layer then
			layers[spec.layer] = e
		end
	end
	return layers
end
local function first(e)
	return e.Color.Keypoints[1].Value
end
local function same(a, b)
	return math.abs(a.R - b.R) < 1e-3 and math.abs(a.G - b.G) < 1e-3 and math.abs(a.B - b.B) < 1e-3
end

local oldPresetsUntouched = true
for _, name in names do
	local preset = Vfx.Presets[name]
	if preset.variants then
		continue
	end
	for index, spec in preset.emitters do
		local e = Vfx.build(name):FindFirstChild(`{name}{index}`)
		local expected = (spec.color or { roblox.Color3.new(1, 1, 1) })[1]
		if spec.flipbook or e.FlipbookLayout ~= Layout.None or not same(first(e), expected) then
			oldPresetsUntouched = false
			print(`    {name}/{e.Name}: layout {e.FlipbookLayout}, color {first(e)}`)
		end
	end
end
check(oldPresetsUntouched, "presets without layers keep no flipbook and their own colors")

local slash = Vfx.build("Slash")
local layers = byLayer(slash, "Slash")
local sheetOnly, aligned = true, true
for _, e in emitters(slash) do
	if e.FlipbookLayout ~= Layout.Grid4x4 or e.FlipbookMode ~= Mode.OneShot or e.Texture ~= emitters(slash)[1].Texture then
		sheetOnly = false
	end
	if e.Rotation.Min ~= 0 or e.Rotation.Max ~= 0 or e.Speed.Max ~= 0 then
		aligned = false
	end
end
check(layers.Glow and layers.Body and layers.Core and #emitters(slash) == 3, "Slash stacks three layers (Glow, Body, Core)")
check(sheetOnly, "every layer plays the same 4x4 sheet once (Grid4x4, OneShot)")
check(aligned, "layers share rotation and position, so they stay stacked")
check(layers.Core.ZOffset > layers.Body.ZOffset and layers.Body.ZOffset > layers.Glow.ZOffset, "draw order glow < body < core")
Vfx.Textures.SlashSheet = "rbxassetid://456"
check(emitters(Vfx.build("Slash"))[1].Texture == "rbxassetid://456", "the uploaded sheet id is used")

local variants = Vfx.variants("Slash")
check(#variants == 2 and variants[1] == "Ember" and variants[2] == "Frost" and #Vfx.variants("HitSpark") == 0, "Vfx.variants lists the color variants")
local ember, frost = byLayer(Vfx.build("Slash", { variant = "Ember" }), "Slash"), byLayer(Vfx.build("Slash", { variant = "Frost" }), "Slash")
local perLayer = true
for layer, colors in Vfx.Presets.Slash.variants.Ember do
	perLayer = perLayer and same(first(ember[layer]), colors[1])
end
for layer, colors in Vfx.Presets.Slash.variants.Frost do
	perLayer = perLayer and same(first(frost[layer]), colors[1])
end
check(perLayer, "a variant colors each layer on its own")
check(not same(first(ember.Body), first(frost.Body)) and not same(first(ember.Glow), first(ember.Core)), "variants differ, layers within a variant differ")
local custom = byLayer(Vfx.build("Slash", { variant = "Ember", layerColors = { Core = { roblox.Color3.new(0, 1, 0) } } }), "Slash")
check(same(first(custom.Core), roblox.Color3.new(0, 1, 0)) and same(first(custom.Body), first(ember.Body)), "layerColors overrides one layer and keeps the variant for the rest")
local tintAll = Vfx.build("Slash", { color = Vfx.Rarity.Rare })
local allTinted = true
for _, e in emitters(tintAll) do
	allTinted = allTinted and same(first(e), Vfx.Rarity.Rare)
end
check(allTinted, "the color option still tints every layer")
check(not pcall(Vfx.build, "Slash", { variant = "Poison" }), "an unknown variant is an error")

local low = byLayer(Vfx.build("Slash", { quality = 0.3 }), "Slash")
check(low.Glow == nil and low.Body and low.Core, "low quality drops the big glow layer (fill-rate), keeps the slash")
local calm = byLayer(Vfx.build("Slash", { reducedFlashing = true, variant = "Frost" }), "Slash")
check(calm.Glow and calm.Body and calm.Core, "reduced flashing keeps every slash layer (nothing in it flashes)")
Vfx.Presets.TestSparkle = {
	kind = "loop",
	emitters = {
		{
			texture = "SlashSheet",
			flipbook = { layout = "Grid2x2", mode = "Random", framerate = 12, startRandom = true },
			rate = 4,
			lifetime = { 1, 1 },
			speed = { 0, 0 },
			size = { { 0, 1 }, { 1, 1 } },
			transparency = { { 0, 0 }, { 1, 1 } },
		},
	},
}
local sparkle = emitters(Vfx.build("TestSparkle"))[1]
check(sparkle.FlipbookLayout == Layout.Grid2x2 and sparkle.FlipbookMode == Mode.Random and sparkle.FlipbookFramerate.Min == 12 and sparkle.FlipbookStartRandom, "flipbook options map to FlipbookLayout/Mode/Framerate/StartRandom")
check(emitters(Vfx.build("TestSparkle", { reducedFlashing = true }))[1].FlipbookMode == Mode.Loop, "reduced flashing turns Random frame jumps into Loop")
Vfx.Presets.TestSparkle = nil

print("AnimationSet")
local AnimationSet = load(`{ASSETS}/AnimationSet.luau`)

local function fakeAnimator()
	local animator = { loaded = {} }
	function animator:LoadAnimation(animation)
		local track = { Name = animation.Name, Id = animation.AnimationId, IsPlaying = false, params = {}, signals = {}, destroyed = false }
		function track:Play(fade, weight, speed)
			self.IsPlaying = true
			self.played = { fade, weight, speed }
		end
		function track:Stop()
			self.IsPlaying = false
		end
		function track:GetMarkerReachedSignal(marker)
			local signal = { handlers = {} }
			function signal:Connect(fn)
				table.insert(self.handlers, fn)
				local connection = { connected = true }
				function connection:Disconnect()
					self.connected = false
				end
				return connection
			end
			self.signals[marker] = signal
			return signal
		end
		function track:SetParameter(name, value)
			self.params[name] = value
		end
		function track:Destroy()
			self.destroyed = true
		end
		self.loaded[animation.Name] = track
		return track
	end
	return animator
end

local specsSource = process.args[1]
local specs = if specsSource
	then load(specsSource).Specs
	else {
		Idle = { Id = "rbxassetid://11", Priority = roblox.Enum.AnimationPriority.Idle, Looped = true, Markers = {} },
		Chop = { Id = "rbxassetid://12", Priority = roblox.Enum.AnimationPriority.Action, Looped = false, Markers = { "Hit" } },
		Locomotion = { Id = "rbxassetid://13", Graph = true, Parameters = { "Speed" }, Markers = {} },
		Victory = { Id = "rbxassetid://0", Priority = roblox.Enum.AnimationPriority.Action, Looped = false, Markers = {} },
	}
local animator = fakeAnimator()
table.clear(warnings)
local set = AnimationSet.new(animator, specs)
check(animator.loaded.Chop and animator.loaded.Chop.Priority == roblox.Enum.AnimationPriority.Action and animator.loaded.Chop.Looped == false, "priority and looping applied from the spec")
check(animator.loaded.Idle and animator.loaded.Idle.Looped == true, "idle loops")
check(animator.loaded.Victory == nil and #warnings == 1 and string.find(warnings[1], "Victory") ~= nil, "missing ids skipped with one warning")
check(set:play("Victory") == nil, "playing a missing animation is a no-op")
set:play("Chop", { fade = 0.2, speed = 1.5 })
check(set:isPlaying("Chop") and animator.loaded.Chop.played[1] == 0.2 and animator.loaded.Chop.played[3] == 1.5, "play with fade/speed")
local hits = 0
local connection = set:onMarker("Chop", "Hit", function()
	hits += 1
end)
animator.loaded.Chop.signals.Hit.handlers[1]("")
check(hits == 1, "marker callback fires")
table.clear(warnings)
set:onMarker("Chop", "Swoosh", function() end)
check(#warnings == 1, "unknown marker warns")
set:setParameter("Locomotion", "Speed", 12)
check(animator.loaded.Locomotion.params.Speed == 12, "graph parameter forwarded to SetParameter")
check(animator.loaded.Locomotion.Priority == nil, "graph tracks keep their own priority")
set:stop("Chop")
check(not set:isPlaying("Chop"), "stop")
set:destroy()
check(not connection.connected and animator.loaded.Idle.destroyed, "destroy disconnects markers and destroys tracks")

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
