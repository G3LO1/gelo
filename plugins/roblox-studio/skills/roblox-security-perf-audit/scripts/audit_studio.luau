--!nocheck
-- Place audit: security + performance findings for the whole DataModel.
-- Read-only: it never changes the place.
--
-- In Studio: paste this whole file into execute_luau (Roblox Studio MCP) or the Command Bar;
-- it prints the report and returns it as a string.
-- On a place/model file: lune run audit_place.luau <file.rbxl|.rbxlx|.rbxm|.rbxmx> (loads this file
-- with AUDIT_RETURN = true and calls Audit.run itself).
--
-- Numbers are starting points to investigate, not Roblox limits. Measure on a real phone
-- (Developer Console, MicroProfiler, Scene Analysis) before and after fixing.

local Audit = {}

Audit.Thresholds = {
	ShadowLights = 8, -- local lights with Shadows on in the place
	SmallShadowCasterSize = 2, -- studs: parts smaller than this rarely need CastShadow
	SmallShadowCasters = 200,
	EmitterRateMax = 400, -- per emitter cap (100 on mobile)
	EmitterRateMobile = 100,
	TotalParticleRate = 1500, -- sum of Rate over enabled emitters
	ParticleLifetimeMax = 20, -- engine cap
	PreciseCollision = 50,
	TinyCollidable = 300, -- parts under 1 stud that still collide
	TransparentParts = 800,
	NpcHumanoids = 40,
	PartsWithoutStreaming = 20000,
	LargeModelParts = 3000,
	UniqueMeshes = 600,
}

local SUSPICIOUS = {
	{ pattern = "require%s*%(%s*%d%d%d%d+", what = "require() of an asset id" },
	{ pattern = "require%s*%(%s*tonumber", what = "require() of a computed id" },
	{ pattern = "loadstring%s*%(", what = "loadstring()" },
	{ pattern = "getfenv%s*%(", what = "getfenv()" },
	{ pattern = "setfenv%s*%(", what = "setfenv()" },
	{ pattern = "discord%.com/api/webhooks", what = "Discord webhook" },
	{ pattern = "discordapp%.com/api/webhooks", what = "Discord webhook" },
	{ pattern = "pastebin%.com", what = "paste site" },
	{ pattern = "\\%d%d%d?\\%d%d%d?\\%d%d%d?\\%d%d%d?\\%d%d%d?\\%d%d%d?\\%d%d%d?\\%d%d%d?", what = "escaped byte string" },
	{ pattern = "%S[ \t][ \t][ \t][ \t][ \t][ \t][ \t][ \t][ \t][ \t]" .. string.rep("[ \t]", 110) .. "%S", what = "code hidden off-screen with whitespace" },
}

local function get(instance, property, default)
	local ok, value = pcall(function()
		return instance[property]
	end)
	if ok and value ~= nil then
		return value
	end
	return default
end

local function path(instance)
	local ok, name = pcall(function()
		return instance:GetFullName()
	end)
	return ok and name or instance.Name
end

local function maxSize(part)
	local size = get(part, "Size", nil)
	if not size then
		return 0
	end
	return math.max(size.X, size.Y, size.Z)
end

-- Nearest ancestor that is a plain Model (Workspace itself inherits from Model).
local function modelOf(instance)
	local ancestor = instance.Parent
	while ancestor and ancestor.Parent do
		if ancestor.ClassName == "Model" then
			return ancestor
		end
		ancestor = ancestor.Parent
	end
	return nil
end

-- Everything under the services Studio lets scripts read (CoreGui and friends can throw).
local function allDescendants(game)
	local out = {}
	for _, service in game:GetChildren() do
		local ok, list = pcall(function()
			return service:GetDescendants()
		end)
		if ok then
			for _, item in list do
				table.insert(out, item)
			end
		end
	end
	return out
end

local function enumName(value)
	local text = tostring(value)
	return string.match(text, "([%w_]+)%)?>?$") or text
end

function Audit.run(game)
	local workspace = game:GetService("Workspace")
	local report = { findings = {}, stats = {} }
	local stats = report.stats
	local T = Audit.Thresholds

	local function add(severity, rule, message, examples)
		table.insert(report.findings, { severity = severity, rule = rule, message = message, examples = examples or {} })
	end

	local function sample(list, limit)
		local out = {}
		for i = 1, math.min(#list, limit or 5) do
			out[i] = list[i]
		end
		return out
	end

	-- Scripts anywhere in the place (Toolbox models hide them in Workspace, Lighting, ...).
	local scriptsOutsideCode, suspicious = {}, {}
	stats.scripts = 0
	for _, descendant in allDescendants(game) do
		if descendant:IsA("LuaSourceContainer") and descendant.ClassName ~= "CoreScript" then
			stats.scripts += 1
			local source = get(descendant, "Source", "")
			for _, rule in SUSPICIOUS do
				if string.find(source, rule.pattern) then
					table.insert(suspicious, `{path(descendant)} ({rule.what})`)
					break
				end
			end
			if descendant:IsA("Script") and modelOf(descendant) and descendant:IsDescendantOf(workspace) then
				table.insert(scriptsOutsideCode, path(descendant))
			end
		end
	end
	if #suspicious > 0 then
		add("high", "SCRIPT-SUSPICIOUS", `{#suspicious} script(s) contain backdoor patterns. Read them, delete what you didn't write, sandbox the model (Sandboxed + Capabilities).`, sample(suspicious, 10))
	end
	if #scriptsOutsideCode > 0 then
		add("medium", "SCRIPT-IN-MODEL", `{#scriptsOutsideCode} script(s) live inside Workspace models (typical for Toolbox assets). Check each one, or sandbox the model.`, sample(scriptsOutsideCode, 10))
	end
	local loadString = get(game:GetService("ServerScriptService"), "LoadStringEnabled", false)
	if loadString == true then
		add("high", "LOADSTRING-ENABLED", "ServerScriptService.LoadStringEnabled is on: any loadstring() backdoor can run code. Turn it off.")
	end

	-- Geometry, physics, rendering.
	local parts, unanchored, precise, tinyCollide, smallShadow, transparent = 0, {}, 0, 0, 0, 0
	local meshIds, meshParts, unions, npcs = {}, 0, 0, {}
	local lightsWithShadows, emitters, totalRate = {}, 0, 0
	local hotEmitters, mobileEmitters, longLifetime = {}, {}, {}
	local decals, sounds, loopingSounds = 0, 0, 0
	local modelParts = {}
	local fidelityUnknown = 0

	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d.ClassName ~= "Terrain" then
			parts += 1
			local character = modelOf(d)
			local inHumanoidModel = character and character:FindFirstChildOfClass("Humanoid") ~= nil
			local inTool = d:FindFirstAncestorWhichIsA("Tool") ~= nil
			if get(d, "Anchored", false) == false and not inHumanoidModel and not inTool then
				local jointed = false
				for _, child in d:GetChildren() do
					if child:IsA("JointInstance") or child:IsA("Constraint") or child:IsA("WeldConstraint") then
						jointed = true
						break
					end
				end
				if not jointed then
					table.insert(unanchored, path(d))
				end
			end
			if d:IsA("MeshPart") then
				meshParts += 1
				local id = get(d, "MeshId", "")
				if id ~= "" then
					meshIds[id] = true
				end
			elseif d:IsA("UnionOperation") then
				unions += 1
			end
			if d:IsA("TriangleMeshPart") then
				local fidelity = get(d, "CollisionFidelity", nil)
				if fidelity == nil then
					fidelityUnknown += 1
				elseif enumName(fidelity) == "PreciseConvexDecomposition" then
					precise += 1
				end
			end
			local size = maxSize(d)
			if size < 1 and get(d, "CanCollide", true) then
				tinyCollide += 1
			end
			if size < T.SmallShadowCasterSize and get(d, "CastShadow", true) then
				smallShadow += 1
			end
			local transparency = get(d, "Transparency", 0)
			if transparency > 0 and transparency < 1 then
				transparent += 1
			end
			if character then
				-- keyed by path: outside Studio the same instance can come back as a new object
				local key = path(character)
				modelParts[key] = (modelParts[key] or 0) + 1
			end
		elseif d:IsA("Humanoid") then
			local model = d.Parent
			local isPlayer = false
			pcall(function()
				isPlayer = game:GetService("Players"):GetPlayerFromCharacter(model) ~= nil
			end)
			if not isPlayer then
				table.insert(npcs, path(model))
			end
		elseif d:IsA("Light") then
			if get(d, "Shadows", false) and get(d, "Enabled", true) then
				table.insert(lightsWithShadows, path(d))
			end
		elseif d:IsA("ParticleEmitter") then
			emitters += 1
			local rate = get(d, "Rate", 0)
			if get(d, "Enabled", true) then
				totalRate += rate
			end
			if rate > T.EmitterRateMax then
				table.insert(hotEmitters, `{path(d)} (Rate {rate})`)
			elseif rate > T.EmitterRateMobile then
				table.insert(mobileEmitters, `{path(d)} (Rate {rate})`)
			end
			local lifetime = get(d, "Lifetime", nil)
			if lifetime and lifetime.Max > T.ParticleLifetimeMax then
				table.insert(longLifetime, path(d))
			end
		elseif d:IsA("Decal") then
			decals += 1
		elseif d:IsA("Sound") then
			sounds += 1
			if get(d, "Looped", false) and get(d, "Playing", false) then
				loopingSounds += 1
			end
		end
	end

	local uniqueMeshes = 0
	for _ in meshIds do
		uniqueMeshes += 1
	end
	stats.workspaceInstances = #workspace:GetDescendants()
	stats.parts = parts
	stats.meshParts = meshParts
	stats.uniqueMeshes = uniqueMeshes
	stats.unions = unions
	stats.preciseCollision = precise
	if fidelityUnknown > 0 then
		-- Lune can't read CollisionFidelity back from saved files; Studio always can.
		stats.collisionFidelityUnreadable = fidelityUnknown
	end
	stats.npcHumanoids = #npcs
	stats.particleEmitters = emitters
	stats.totalParticleRate = totalRate
	stats.shadowLights = #lightsWithShadows
	stats.decalsAndTextures = decals
	stats.sounds = sounds
	stats.loopingSounds = loopingSounds

	if #unanchored > 0 then
		add("medium", "UNANCHORED", `{#unanchored} loose unanchored part(s) outside characters/tools: physics cost and things falling apart. Anchor static geometry.`, sample(unanchored))
	end
	if precise > T.PreciseCollision then
		add("medium", "PRECISE-COLLISION", `{precise} meshes/unions use PreciseConvexDecomposition. Use Box/Hull for props and invisible simple colliders for walkways.`)
	elseif precise > 0 then
		add("low", "PRECISE-COLLISION", `{precise} meshes/unions use PreciseConvexDecomposition; keep it for the few that need exact collision.`)
	end
	if tinyCollide > T.TinyCollidable then
		add("low", "TINY-COLLIDABLE", `{tinyCollide} parts smaller than 1 stud still collide. Decor: CanCollide/CanTouch/CanQuery off.`)
	end
	if smallShadow > T.SmallShadowCasters then
		add("low", "SMALL-SHADOWS", `{smallShadow} small parts (< {T.SmallShadowCasterSize} studs) cast shadows. Turn CastShadow off on small decor.`)
	end
	if transparent > T.TransparentParts then
		add("low", "OVERDRAW", `{transparent} semi-transparent parts: transparency overdraw is expensive on phones.`)
	end
	if #lightsWithShadows > T.ShadowLights then
		add("medium", "SHADOW-LIGHTS", `{#lightsWithShadows} local lights cast shadows. Keep shadows on a few key lights only.`, sample(lightsWithShadows))
	end
	if #hotEmitters > 0 then
		add("high", "PARTICLE-RATE", `{#hotEmitters} emitter(s) above {T.EmitterRateMax}/s (engine cap; mobile caps at {T.EmitterRateMobile}/s). Lower Rate, use bigger/fewer particles or Emit() bursts.`, sample(hotEmitters))
	end
	if #mobileEmitters > 0 then
		add("medium", "PARTICLE-RATE-MOBILE", `{#mobileEmitters} emitter(s) above {T.EmitterRateMobile}/s: phones cap them, so they look different there and cost more on PC.`, sample(mobileEmitters))
	end
	if totalRate > T.TotalParticleRate then
		add("medium", "PARTICLE-BUDGET", `Enabled emitters spawn {totalRate} particles/s in total. Disable emitters out of view, lower rates.`)
	end
	if #longLifetime > 0 then
		add("low", "PARTICLE-LIFETIME", `{#longLifetime} emitter(s) have Lifetime above 20 s, which the engine caps at 20.`, sample(longLifetime))
	end
	if #npcs > T.NpcHumanoids then
		add("medium", "NPC-HUMANOIDS", `{#npcs} non-player Humanoids in Workspace. Disable unused HumanoidStateTypes, play NPC animations on clients, use AnimationController for static NPCs, pool and spawn near players.`, sample(npcs))
	end
	if uniqueMeshes > T.UniqueMeshes then
		add("medium", "UNIQUE-MESHES", `{uniqueMeshes} different MeshIds: each unique mesh is a separate asset in memory and breaks instancing. Reuse a modular kit.`)
	end
	local bigModels = {}
	for model, count in modelParts do
		if count > T.LargeModelParts then
			table.insert(bigModels, `{model} ({count} parts)`)
		end
	end
	if #bigModels > 0 then
		table.sort(bigModels)
		add("low", "LARGE-MODELS", `{#bigModels} model(s) hold more than {T.LargeModelParts} parts: split them so streaming and FastCluster rebuilds stay cheap.`, sample(bigModels))
	end

	-- Place settings.
	local streaming = get(workspace, "StreamingEnabled", nil)
	stats.streamingEnabled = streaming
	if streaming == false and parts > T.PartsWithoutStreaming then
		add("medium", "NO-STREAMING", `{parts} parts with StreamingEnabled off: every client loads the whole map. Turn on instance streaming (and make client code streaming-safe).`)
	end
	local destroy = get(workspace, "PlayerCharacterDestroyBehavior", nil)
	if destroy ~= nil and enumName(destroy) ~= "Enabled" then
		add("low", "CHARACTER-CLEANUP", "Workspace.PlayerCharacterDestroyBehavior is not Enabled: characters/players of leavers can leak memory unless your code destroys them.")
	end

	local lighting = game:GetService("Lighting")
	local effectCounts = {}
	for _, child in lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") then
			effectCounts[child.ClassName] = (effectCounts[child.ClassName] or 0) + 1
		end
	end
	for className, count in effectCounts do
		if count > 1 then
			add("low", "STACKED-POSTFX", `{count} {className} objects in Lighting stack on top of each other (often template + custom). Keep one.`)
		end
	end

	local order = { high = 1, medium = 2, low = 3 }
	table.sort(report.findings, function(a, b)
		if order[a.severity] ~= order[b.severity] then
			return order[a.severity] < order[b.severity]
		end
		return a.rule < b.rule
	end)
	return report
end

function Audit.format(report)
	local lines = { "== Place audit ==" }
	local keys = {}
	for key in report.stats do
		table.insert(keys, key)
	end
	table.sort(keys)
	local stats = {}
	for _, key in keys do
		table.insert(stats, `{key}={tostring(report.stats[key])}`)
	end
	table.insert(lines, "stats: " .. table.concat(stats, ", "))
	local totals = { high = 0, medium = 0, low = 0 }
	for _, finding in report.findings do
		totals[finding.severity] += 1
		table.insert(lines, `{string.upper(finding.severity)} {finding.rule}: {finding.message}`)
		for _, example in finding.examples do
			table.insert(lines, `    - {example}`)
		end
	end
	table.insert(lines, `{totals.high} high, {totals.medium} medium, {totals.low} low`)
	return table.concat(lines, "\n"), totals
end

if AUDIT_RETURN then
	return Audit
end
local text = Audit.format(Audit.run(game))
print(text)
return text
