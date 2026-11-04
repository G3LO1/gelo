-- The Bringforth Studio plugin against the real `bringforth.py serve` feed, with a mocked Studio
-- (plugin toolbar, HttpService over @lune/net, InsertService, ChangeHistoryService, Selection).
-- Usage: lune run tests/roblox-bringforth/plugin_test.luau <BringforthPlugin.lua> <feed url> <lock file>

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local PLUGIN, FEED, LOCK = process.args[1], process.args[2], process.args[3]
assert(PLUGIN and FEED and LOCK, "usage: plugin_test.luau <plugin> <feed url> <lock file>")

local passed, failed = 0, 0
local function check(condition: any, message: string)
	if condition then
		passed += 1
		print(`  ok   {message}`)
	else
		failed += 1
		print(`  FAIL {message}`)
	end
end

local function waitUntil(predicate: () -> boolean, timeout: number?): boolean
	local deadline = os.clock() + (timeout or 5)
	while os.clock() < deadline do
		if predicate() then
			return true
		end
		task.wait(0.05)
	end
	return false
end

task.delay(60, function()
	print(`TIMEOUT: {passed} passed, {failed} failed`)
	process.exit(2)
end)

-- Mini Studio ------------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end
function Signal:Connect(fn)
	table.insert(self.handlers, fn)
	return { Disconnect = function() end }
end
function Signal:Fire(...)
	for _, fn in self.handlers do
		task.spawn(fn, ...)
	end
end

local Instance = {}
Instance.__index = function(self, key)
	if Instance[key] then
		return Instance[key]
	end
	for _, child in rawget(self, "_children") do
		if child.Name == key then
			return child
		end
	end
	return nil
end
Instance.__newindex = function(self, key, value)
	if key == "Parent" then
		local old = rawget(self, "_parent")
		if old then
			local list = rawget(old, "_children")
			table.remove(list, table.find(list, self))
		end
		rawset(self, "_parent", value)
		if value then
			table.insert(rawget(value, "_children"), self)
		end
	else
		rawset(self, key, value)
	end
end
function Instance.new(className: string, name: string?)
	return setmetatable({ ClassName = className, Name = name or className, _children = {}, _attributes = {} }, Instance)
end
function Instance:FindFirstChild(name)
	for _, child in rawget(self, "_children") do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function Instance:GetChildren()
	return table.clone(rawget(self, "_children"))
end
function Instance:IsA(className)
	return self.ClassName == className or (className == "PVInstance" and (self.ClassName == "Model" or self.ClassName == "MeshPart"))
end
function Instance:SetAttribute(name, value)
	rawget(self, "_attributes")[name] = value
end
function Instance:GetAttribute(name)
	return rawget(self, "_attributes")[name]
end
function Instance:GetFullName()
	local parts, current = {}, self
	while current do
		table.insert(parts, 1, current.Name)
		current = rawget(current, "_parent")
	end
	return table.concat(parts, ".")
end
function Instance:Destroy()
	self.Parent = nil
	rawset(self, "destroyed", true)
end
function Instance:GetPivot()
	return rawget(self, "pivot") or roblox.CFrame.new()
end
function Instance:PivotTo(cframe)
	rawset(self, "pivot", cframe)
end

local workspaceInst = Instance.new("Workspace", "Workspace")
local map = Instance.new("Folder", "Map")
map.Parent = workspaceInst
local props = Instance.new("Folder", "Props")
props.Parent = map
rawset(workspaceInst, "CurrentCamera", {
	CFrame = roblox.CFrame.lookAt(roblox.Vector3.new(0, 10, 0), roblox.Vector3.new(0, 10, -10)),
})

local loads, recordings, selections, settings = {}, {}, {}, {}
local feedUp = true
local buttons = {}

local services = {
	HttpService = {
		GetAsync = function(_, url: string, _noCache: boolean?)
			if not feedUp then
				error("HttpError: ConnectFail")
			end
			local response = net.request({ url = url, method = "GET" })
			if not response.ok then
				error(`HTTP {response.statusCode}`)
			end
			return response.body
		end,
		JSONDecode = function(_, text: string)
			return serde.decode("json", text)
		end,
	},
	InsertService = {
		LoadAsset = function(_, assetId: number)
			table.insert(loads, assetId)
			if assetId == 404 then
				error("Asset is not trusted for this place")
			end
			local container = Instance.new("Model", "Model")
			local model = Instance.new("Model", `Asset{assetId}`)
			model.Parent = container
			return container
		end,
	},
	ChangeHistoryService = {
		TryBeginRecording = function(_, name)
			table.insert(recordings, { name = name, finished = nil })
			return #recordings
		end,
		FinishRecording = function(_, id, operation)
			recordings[id].finished = operation
		end,
	},
	Selection = {
		Set = function(_, list)
			table.insert(selections, list)
		end,
	},
}

local game = {
	GetService = function(_, name)
		return assert(services[name], `mock has no service {name}`)
	end,
}

local plugin = {
	Unloading = Signal.new(),
	CreateToolbar = function(_, name)
		return {
			Name = name,
			CreateButton = function(_, text, _tooltip, _icon)
				local button = { Text = text, Click = Signal.new(), active = false }
				function button.SetActive(self, on)
					self.active = on
				end
				buttons[text] = button
				return button
			end,
		}
	end,
	GetSetting = function(_, key)
		return settings[key]
	end,
	SetSetting = function(_, key, value)
		settings[key] = value
	end,
}

local warnings, prints = {}, {}
local source = fs.readFile(PLUGIN)
source = string.gsub(source, 'local FEED_URL = "[^"]*"', `local FEED_URL = "{FEED}"`)
source = string.gsub(source, "local POLL_SECONDS = %d+", "local POLL_SECONDS = 0.1")
local chunk = luau.load(source, {
	debugName = "BringforthPlugin",
	environment = {
		game = game,
		plugin = plugin,
		workspace = workspaceInst,
		CFrame = roblox.CFrame,
		Enum = roblox.Enum,
		task = task,
		warn = function(...)
			table.insert(warnings, table.concat({ ... }, " "))
		end,
		print = function(...)
			table.insert(prints, table.concat({ ... }, " "))
		end,
	},
})
chunk()

-- Tests ------------------------------------------------------------------------------------

local lock = serde.decode("json", fs.readFile(LOCK))
local models = {}
for file, entry in lock.assets do
	if entry.assetType == "Model" then
		table.insert(models, { file = file, id = entry.assetId, at = entry.uploadedAt })
	end
end
table.sort(models, function(a, b)
	return if a.at == b.at then a.file < b.file else a.at < b.at
end)
local latest = models[#models]

print("toolbar")
check(buttons["Import latest"] and buttons["Auto import"], "Import latest and Auto import buttons")

print("import latest")
buttons["Import latest"].Click:Fire()
check(waitUntil(function()
	return #props:GetChildren() == 1
end), "one model inserted")
local inserted = props:GetChildren()[1]
check(loads[1] == latest.id, `loaded the newest model upload ({latest.file})`)
check(inserted and inserted.Name == `Asset{latest.id}` and inserted:GetAttribute("BringforthAssetId") == latest.id, "inserted into Workspace.Map.Props, tagged with its asset ID")
check(inserted and inserted:GetAttribute("BringforthFile") == latest.file, "tagged with its source file")
local pivot = inserted and inserted:GetPivot()
-- Expected spot from the same camera (Lune's CFrame.LookVector sign differs from Roblox's, so compute it).
local camera = workspaceInst.CurrentCamera.CFrame
local expected = camera.Position + camera.LookVector * 24
check(pivot and (pivot.Position - expected).Magnitude < 0.01, "placed 24 studs along the camera's look direction")
check(recordings[1] and recordings[1].finished == roblox.Enum.FinishRecordingOperation.Commit, "one undoable ChangeHistory step")
check(selections[1] and selections[1][1] == inserted, "the new model is selected")
check(type(settings.BringforthSeen) == "table" and #settings.BringforthSeen == 1, "remembered as imported")

print("auto import")
buttons["Auto import"].Click:Fire()
check(waitUntil(function()
	return buttons["Auto import"].active
end), "button shows active")
task.wait(0.4)
check(#props:GetChildren() == 1, "uploads from before auto import are not inserted")

lock.assets["models/new_rock.fbx"] = {
	assetId = 424242,
	assetType = "Model",
	name = "new_rock",
	version = "1",
	uploadedAt = "2999-01-01T00:00:00+00:00",
	moderation = "approved",
	sha256 = "x",
}
lock.assets["textures/new.png"] = { assetId = 515151, assetType = "Decal", name = "new", version = "1", uploadedAt = "2999-01-01T00:00:01+00:00" }
fs.writeFile(LOCK, serde.encode("json", lock))
check(waitUntil(function()
	return #props:GetChildren() == 2
end), "a new model upload is inserted automatically")
task.wait(0.4)
check(#props:GetChildren() == 2 and not table.find(loads, 515151), "inserted once, images are not inserted")

lock.assets["models/new_rock.fbx"].version = "2"
fs.writeFile(LOCK, serde.encode("json", lock))
check(waitUntil(function()
	return #props:GetChildren() == 3
end), "a new FBX version is inserted again")

lock.assets["models/flagged.glb"] = { assetId = 999, assetType = "Model", name = "flagged", version = "1", uploadedAt = "2999-01-02T00:00:00+00:00", moderation = "rejected" }
lock.assets["models/foreign.glb"] = { assetId = 404, assetType = "Model", name = "foreign", version = "1", uploadedAt = "2999-01-03T00:00:00+00:00", moderation = "approved" }
fs.writeFile(LOCK, serde.encode("json", lock))
check(waitUntil(function()
	return table.find(loads, 404) ~= nil
end), "keeps polling")
task.wait(0.3)
check(not table.find(loads, 999), "moderation-rejected asset is not loaded")
local function warned(pattern: string): boolean
	for _, message in warnings do
		if string.find(message, pattern) then
			return true
		end
	end
	return false
end
check(warned("moderation rejected"), "rejected asset warned")
check(warned("could not load asset 404"), "failed LoadAsset warned instead of crashing")
check(recordings[#recordings].finished == roblox.Enum.FinishRecordingOperation.Cancel, "failed insert cancels its ChangeHistory step")

feedUp = false
task.wait(0.3)
check(warned("feed not reachable"), "feed down: warns and keeps the plugin alive")
feedUp = true

buttons["Auto import"].Click:Fire()
task.wait(0.2)
check(not buttons["Auto import"].active, "auto import turns off")
local count = #loads
lock.assets["models/after.glb"] = { assetId = 777, assetType = "Model", name = "after", version = "1", uploadedAt = "2999-02-01T00:00:00+00:00" }
fs.writeFile(LOCK, serde.encode("json", lock))
task.wait(0.4)
check(#loads == count, "nothing inserted while auto import is off")

print()
print(`{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
