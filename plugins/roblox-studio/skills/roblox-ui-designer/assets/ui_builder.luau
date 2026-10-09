-- UI builder: turns a ui-spec table (see references/ui-spec.md) into Roblox instances.
-- spec_to_luau.py prepends `local SPEC = {...}` and appends `run(SPEC)`, producing one
-- script to run in the Studio Command Bar or through the Studio MCP execute_luau tool.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Lets validate_ui.luau check style rules under Lune; empty in Studio.
-- selene: allow(global_usage)
local hooks = _G.UI_BUILDER_HOOKS or {}

local function color(hex: string): Color3
	local r, g, b = string.match(hex, "^#(%x%x)(%x%x)(%x%x)$")
	assert(r, `Bad color "{hex}", expected #RRGGBB`)
	return Color3.fromRGB(tonumber(r, 16) :: number, tonumber(g, 16) :: number, tonumber(b, 16) :: number)
end

local function fontFace(font: any): Font
	local family = font.family
	if not string.find(family, "://", 1, true) then
		family = `rbxasset://fonts/families/{family}.json`
	end
	return Font.new(
		family,
		(Enum.FontWeight :: any)[font.weight or "Regular"],
		(Enum.FontStyle :: any)[font.style or "Normal"]
	)
end

local decode

local function decodeToken(spec: any, name: string): any
	local token = spec.tokens and spec.tokens[name]
	assert(token ~= nil, `Unknown token "{name}"`)
	return decode(spec, token)
end

function decode(spec: any, value: any): any
	if type(value) ~= "table" then
		return value
	end
	if value.udim2 then
		local v = value.udim2
		return UDim2.new(v[1], v[2], v[3], v[4])
	elseif value.udim then
		return UDim.new(value.udim[1], value.udim[2])
	elseif value.vector2 then
		return Vector2.new(value.vector2[1], value.vector2[2])
	elseif value.rect then
		local v = value.rect
		return Rect.new(v[1], v[2], v[3], v[4])
	elseif value.color then
		return color(value.color)
	elseif value.token then
		return decodeToken(spec, value.token)
	elseif value.enum then
		local enumName, itemName = string.match(value.enum, "^([%w_]+)%.([%w_]+)$")
		assert(enumName, `Bad enum "{value.enum}", expected EnumName.Item`)
		return (Enum :: any)[enumName][itemName]
	elseif value.font then
		local font = value.font
		if type(font) == "string" then
			font = spec.fonts and spec.fonts[font]
			assert(font, `Unknown font "{value.font}"`)
		end
		return fontFace(font)
	elseif value.image then
		local id = spec.images and spec.images[value.image]
		assert(id ~= nil, `Unknown image "{value.image}"`)
		return id
	elseif value.colorseq then
		local keypoints = {}
		for _, point in value.colorseq do
			table.insert(keypoints, ColorSequenceKeypoint.new(point[1], color(point[2])))
		end
		return ColorSequence.new(keypoints)
	elseif value.numseq then
		local keypoints = {}
		for _, point in value.numseq do
			table.insert(keypoints, NumberSequenceKeypoint.new(point[1], point[2]))
		end
		return NumberSequence.new(keypoints)
	end
	local keys = {}
	for key in value do
		table.insert(keys, tostring(key))
	end
	error(`Unknown value encoding with keys: {table.concat(keys, ", ")}`)
end

local count = 0

local function build(spec: any, node: any, parent: Instance?, path: string): Instance
	local here = `{path}/{node.name or node.class}`
	local created, inst = pcall(Instance.new, node.class)
	if not created then
		error(`{here}: unknown class "{node.class}"`, 0)
	end
	inst.Name = node.name or node.class
	for prop, value in node.props or {} do
		local ok, err = pcall(function()
			(inst :: any)[prop] = decode(spec, value)
		end)
		if not ok then
			error(`{here}.{prop}: {err}`, 0)
		end
	end
	for name, value in node.attributes or {} do
		inst:SetAttribute(name, decode(spec, value))
	end
	for _, tag in node.tags or {} do
		inst:AddTag(tag)
	end
	for _, child in node.children or {} do
		build(spec, child, inst, here)
	end
	count += 1
	inst.Parent = parent
	return inst
end

local function buildStyleSheet(spec: any): StyleSheet?
	if not spec.tokens and not spec.styles then
		return nil
	end
	local sheet = Instance.new("StyleSheet")
	sheet.Name = spec.name
	for name, value in spec.tokens or {} do
		sheet:SetAttribute(name, decode(spec, value))
	end
	for index, ruleSpec in spec.styles or {} do
		local rule = Instance.new("StyleRule")
		rule.Name = `Rule{index}`
		rule.Selector = ruleSpec.selector
		rule.Priority = ruleSpec.priority or index
		local props = {}
		for prop, value in ruleSpec.props or {} do
			-- Tokens stay live ("$Name") so editing the sheet restyles everything.
			props[prop] = if type(value) == "table" and value.token then "$" .. value.token else decode(spec, value)
		end
		if hooks.setRuleProperties then
			hooks.setRuleProperties(rule, props, ruleSpec.selector, sheet)
		else
			(rule :: any):SetProperties(props)
		end
		rule.Parent = sheet
	end
	local folder = ReplicatedStorage:FindFirstChild("UIStyles")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "UIStyles"
		folder.Parent = ReplicatedStorage
	end
	local old = folder:FindFirstChild(spec.name)
	if old then
		old:Destroy()
	end
	sheet.Parent = folder
	return sheet
end

-- Called by the line spec_to_luau.py appends.
-- selene: allow(unused_variable)
local function run(spec: any)
	local container = game:GetService(spec.parent or "StarterGui")
	local sheet = buildStyleSheet(spec)
	for _, screen in spec.screens do
		local existing = container:FindFirstChild(screen.name)
		if existing then
			-- Keep the old version instead of deleting someone's work.
			existing.Name = screen.name .. "_Backup"
			if existing:IsA("ScreenGui") then
				existing.Enabled = false
			end
		end
		local gui = build(spec, screen, nil, spec.name)
		if sheet then
			local link = Instance.new("StyleLink")
			link.StyleSheet = sheet
			link.Parent = gui
		end
		gui.Parent = container
	end
	print(`[ui_builder] {spec.name}: built {count} instances into {container.Name}`)
end
