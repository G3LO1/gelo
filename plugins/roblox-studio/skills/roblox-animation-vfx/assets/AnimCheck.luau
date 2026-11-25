--!strict
-- AnimCheck: after the animations are imported and published, check the published clips against
-- the manifest (Animations.luau from anim_manifest.py): every marker the code listens for is on the
-- clip (Blender markers don't always survive the FBX import), and the saved looping and priority
-- match. Checks Specs and, when the game ships R6 too, SpecsR6.
--
-- Studio Command Bar (or the Studio MCP execute_luau tool), with the owner account signed in:
--   local AnimCheck = require(game.ReplicatedStorage.Shared.AnimCheck)
--   AnimCheck.runAll(require(game.ReplicatedStorage.Shared.Animations))
-- Prints one line per problem and returns { checked, problems }. It loads clips with
-- AnimationClipProvider:GetAnimationClipAsync, so it yields; run it in Studio, not in a live server loop.

local AnimCheck = {}

export type Spec = { Id: string, Priority: EnumItem?, Looped: boolean?, Markers: { string }?, Graph: boolean? }
export type Result = { checked: number, problems: { string } }

-- Marker name -> time (seconds) and the clip length, for KeyframeSequence and CurveAnimation clips.
function AnimCheck.collect(clip: Instance): ({ [string]: number }, number?)
	local markers: { [string]: number } = {}
	local length: number? = nil
	if clip:IsA("KeyframeSequence") then
		for _, keyframe in clip:GetChildren() do
			if keyframe:IsA("Keyframe") then
				length = math.max(length or 0, keyframe.Time)
				for _, marker in keyframe:GetChildren() do
					if marker:IsA("KeyframeMarker") and markers[marker.Name] == nil then
						markers[marker.Name] = keyframe.Time
					end
				end
			end
		end
	else
		for _, descendant in clip:GetDescendants() do
			if descendant:IsA("MarkerCurve") then
				for _, marker in (descendant :: any):GetMarkers() do
					markers[marker.Marker] = markers[marker.Marker] or marker.Time
				end
			end
		end
	end
	return markers, length
end

function AnimCheck.run(specs: { [string]: Spec }, options: { provider: any?, label: string?, print: ((string) -> ())? }?): Result
	local opts = options or {}
	local provider = opts.provider or game:GetService("AnimationClipProvider")
	local out = opts.print or print
	local label = opts.label or "Specs"
	local problems = {}
	local checked = 0
	local function problem(message: string)
		table.insert(problems, `{label}.{message}`)
		out(`[AnimCheck] {label}.{message}`)
	end
	local names = {}
	for name in specs do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local spec = specs[name]
		if spec.Graph then
			continue
		end
		if spec.Id == "" or spec.Id == "rbxassetid://0" then
			problem(`{name}: not uploaded yet (id 0)`)
			continue
		end
		local ok, clip = pcall(function()
			return provider:GetAnimationClipAsync(spec.Id)
		end)
		if not ok or clip == nil then
			problem(`{name}: can't load {spec.Id} ({clip}); is it published by the owner of the experience?`)
			continue
		end
		checked += 1
		local markers = AnimCheck.collect(clip)
		for _, marker in spec.Markers or {} do
			if markers[marker] == nil then
				problem(`{name}: marker "{marker}" is missing on the published clip; add it on the events track (Animation Editor) and republish`)
			end
		end
		if spec.Looped ~= nil and (clip :: any).Loop ~= spec.Looped then
			problem(`{name}: published with Loop = {(clip :: any).Loop}, the manifest says {spec.Looped} (AnimationSet sets it at runtime; fix the asset so other code agrees)`)
		end
		if spec.Priority ~= nil and (clip :: any).Priority ~= spec.Priority then
			problem(`{name}: published at {(clip :: any).Priority}, the manifest says {spec.Priority}`)
		end
	end
	out(`[AnimCheck] {label}: {checked} clip(s) checked, {#problems} problem(s)`)
	return { checked = checked, problems = problems }
end

-- Specs, and SpecsR6 when the module has it.
function AnimCheck.runAll(animations: any, options: { provider: any?, print: ((string) -> ())? }?): Result
	local opts = options or {}
	local total = AnimCheck.run(animations.Specs, { provider = opts.provider, print = opts.print, label = "Specs" })
	if animations.SpecsR6 then
		local r6 = AnimCheck.run(animations.SpecsR6, { provider = opts.provider, print = opts.print, label = "SpecsR6" })
		total.checked += r6.checked
		for _, message in r6.problems do
			table.insert(total.problems, message)
		end
	end
	return total
end

return AnimCheck
