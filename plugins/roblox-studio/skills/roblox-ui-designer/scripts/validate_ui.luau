-- Runs a generated UI build script under Lune with Roblox's real class/property database:
-- every property name, value type and enum is checked exactly as Studio would, and style
-- rule properties are checked against the class their selector targets.
-- Writes the built ScreenGuis (+ StyleSheet) to an .rbxmx you can drag into Studio.
--
-- Usage: lune run validate_ui.luau <BuildUi.luau> [out.rbxmx]
-- Note: StyleRule property values are not saved in the .rbxmx (Lune can't set them); every
-- element still carries its resolved properties, so the file looks right on its own. Run the
-- build script in Studio to get live, editable style rules.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local scriptPath = process.args[1]
local outPath = process.args[2]
if not scriptPath then
	print("usage: lune run validate_ui.luau <BuildUi.luau> [out.rbxmx]")
	process.exit(2)
end

local game = roblox.Instance.new("DataModel")
local problems = {}

local function classFromSelector(selector: string): string?
	local last = string.match(selector, "([^%s>]+)%s*$") or selector
	local pseudo = string.match(last, "::(%w+)")
	if pseudo then
		return pseudo
	end
	return string.match(last, "^(%u%w*)")
end

local hooks = {
	setRuleProperties = function(_rule, props, selector, sheet)
		local className = classFromSelector(selector)
		if not className then
			print(`  note: can't infer a class from selector "{selector}", its properties are not type-checked`)
			return
		end
		local okClass, probe = pcall(roblox.Instance.new, className)
		if not okClass then
			table.insert(problems, `style "{selector}": unknown class {className}`)
			return
		end
		for prop, value in props do
			if type(value) == "string" and string.sub(value, 1, 1) == "$" then
				local tokenName = string.sub(value, 2)
				value = sheet:GetAttribute(tokenName)
				if value == nil then
					table.insert(problems, `style "{selector}".{prop}: unknown token ${tokenName}`)
					continue
				end
			end
			local ok, err = pcall(function()
				probe[prop] = value
			end)
			if not ok then
				table.insert(problems, `style "{selector}".{prop}: {string.match(tostring(err), "[^\n]+")}`)
			end
		end
	end,
}

local env = {
	game = game,
	Instance = roblox.Instance,
	Enum = roblox.Enum,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Vector2 = roblox.Vector2,
	Rect = roblox.Rect,
	Font = roblox.Font,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	_G = { UI_BUILDER_HOOKS = hooks },
}

local source = fs.readFile(scriptPath)
local chunk = luau.load(source, { debugName = scriptPath, environment = env })
local ok, err = pcall(chunk)
if not ok then
	table.insert(problems, string.match(tostring(err), "[^\n]+"))
end

if #problems > 0 then
	print(`FAILED: {#problems} problem(s)`)
	for _, problem in problems do
		print(`  - {problem}`)
	end
	process.exit(1)
end

if outPath then
	local roots = {}
	for _, gui in game:GetService("StarterGui"):GetChildren() do
		table.insert(roots, gui)
	end
	local styles = game:GetService("ReplicatedStorage"):FindFirstChild("UIStyles")
	if styles then
		table.insert(roots, styles)
	end
	fs.writeFile(outPath, roblox.serializeModel(roots, true))
	print(`wrote {outPath} ({#roots} root instances)`)
end
print("OK: all properties, types and enums are valid")
