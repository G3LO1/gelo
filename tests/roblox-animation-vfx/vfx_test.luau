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
print("Layered flipbook (ElementBurst)")
local burstPreset = Vfx.Presets.ElementBurst
check(burstPreset ~= nil and table.concat(Vfx.variants("ElementBurst"), ",") == "Fire,Frost", "ElementBurst has Fire and Frost variants")
local flipLayers, atlases = {}, {}
for _, spec in burstPreset.emitters do
	if spec.flipbook then
		table.insert(flipLayers, spec.layer)
		atlases[spec.texture] = true
	end
end
local atlasCount = 0
for _ in atlases do
	atlasCount += 1
end
check(#flipLayers == 2 and atlasCount == 1, `two flipbook layers ({table.concat(flipLayers, ", ")}) on one atlas`)
check(#Vfx.variants("HitSpark") == 0, "presets without variants list none")

local function byLayer(attachment)
	local map = {}
	for _, e in emitters(attachment) do
		map[e:GetAttribute("Layer")] = e
	end
	return map
end
local plain = byLayer(Vfx.build("ElementBurst"))
check(
	plain.Outer.Texture == "rbxasset://textures/particles/sparkles_main.dds"
		and plain.Outer.FlipbookLayout == roblox.Enum.ParticleFlipbookLayout.None,
	"atlas without an uploaded id plays as a plain particle (no flipbook on the sparkle)"
)
Vfx.Textures.Burst4x4 = "rbxassetid://456"
local fire = byLayer(Vfx.build("ElementBurst", { variant = "Fire", quality = 1 }))
local frost = byLayer(Vfx.build("ElementBurst", { variant = "Frost", quality = 1 }))
local flipOk, sameTexture = true, true
for _, layer in flipLayers do
	for _, e in { fire[layer], frost[layer] } do
		if e.FlipbookLayout ~= roblox.Enum.ParticleFlipbookLayout.Grid4x4 or e.FlipbookMode ~= roblox.Enum.ParticleFlipbookMode.OneShot then
			flipOk = false
		end
	end
	if fire[layer].Texture ~= "rbxassetid://456" or frost[layer].Texture ~= fire[layer].Texture then
		sameTexture = false
	end
end
check(flipOk, "flipbook layers use Grid4x4 / OneShot")
check(sameTexture, "both variants play the same uploaded atlas")
local coloursMatch, coloursDiffer = true, true
for layer, colours in burstPreset.variants.Frost do
	local got = frost[layer].Color.Keypoints
	if got[1].Value ~= colours[1] or got[#got].Value ~= colours[#colours] then
		coloursMatch = false
	end
	if fire[layer].Color.Keypoints[1].Value == got[1].Value then
		coloursDiffer = false
	end
end
check(coloursMatch, "every layer takes its colours from the variant")
check(coloursDiffer, "Fire and Frost differ on every layer")
local default = byLayer(Vfx.build("ElementBurst"))
check(default.Core.Color.Keypoints[1].Value == fire.Core.Color.Keypoints[1].Value, "default variant is Fire")
check(not pcall(Vfx.build, "ElementBurst", { variant = "Poison" }), "unknown variant is an error")
check(not pcall(Vfx.build, "HitSpark", { variant = "Fire" }), "variant on a preset without variants is an error")
local override = byLayer(Vfx.build("ElementBurst", { variant = "Frost", color = Vfx.Rarity.Epic }))
check(override.Outer.Color.Keypoints[1].Value == Vfx.Rarity.Epic, "color option still overrides a variant")
local gentle = byLayer(Vfx.build("ElementBurst", { variant = "Frost", quality = 0.3, reducedFlashing = true }))
check(gentle.Flash == nil, "reduced flashing drops the flash layer")
check(
	gentle.Outer and gentle.Core and gentle.Outer.FlipbookLayout == roblox.Enum.ParticleFlipbookLayout.Grid4x4,
	"low quality + reduced flashing keeps both flipbook layers"
)
check(gentle.Embers:GetAttribute("Burst") < frost.Embers:GetAttribute("Burst"), "low quality emits fewer embers")
Vfx.Presets.FlipTest = {
	kind = "loop",
	emitters = {
		{
			texture = "Burst4x4",
			rate = 2,
			lifetime = { 1, 1 },
			speed = { 0, 0 },
			size = { { 0, 1 }, { 1, 1 } },
			transparency = { { 0, 0 }, { 1, 1 } },
			flipbook = { layout = "Grid4x4", mode = "Loop", framerate = 60, startRandom = true },
		},
	},
}
local looping = emitters(Vfx.build("FlipTest"))[1]
check(
	looping.FlipbookFramerate.Max == Vfx.MaxFlipbookFramerate and looping.FlipbookStartRandom,
	"loop framerate capped at 30, random start"
)
Vfx.Presets.FlipTest = nil

local tinted = Vfx.build("RarityGlow", { color = Vfx.Rarity.Legendary })
check(emitters(tinted)[1].Color.Keypoints[1].Value == Vfx.Rarity.Legendary, "color option tints the effect")
local trail = Vfx.build("SpeedTrail")
local t = trail:FindFirstChildOfClass("Trail")
check(t ~= nil and t.Attachment0 ~= nil and t.Attachment1 ~= nil, "trail preset wires two attachments")
check(emitters(Vfx.build("HitSpark"))[1].Texture == "rbxasset://textures/particles/sparkles_main.dds", "unset texture ids fall back to the engine sparkle")
Vfx.Textures.Spark = "rbxassetid://123"
check(emitters(Vfx.build("HitSpark"))[1].Texture == "rbxassetid://123", "uploaded texture ids are used")
check(Vfx.scaled(10, 0) == 0 and Vfx.scaled(10, 1) == 10 and Vfx.scaled(1, 0.1) == 1, "Vfx.scaled keeps visible effects visible")

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
