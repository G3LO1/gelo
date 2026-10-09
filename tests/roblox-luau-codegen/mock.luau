-- Minimal Roblox engine mock for running the roblox-luau-codegen template under Lune.
-- Each "world" is one game server; worlds can share a DataStore backend to simulate
-- players hopping between servers.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local Mock = {}

-- Signal ----------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {}, waiting = {} }, Signal)
end

function Signal:Connect(fn)
	local connection = { Connected = true }
	function connection.Disconnect(conn)
		conn.Connected = false
	end
	table.insert(self.handlers, { fn = fn, connection = connection })
	return connection
end

function Signal:Fire(...)
	for _, entry in table.clone(self.handlers) do
		if entry.connection.Connected then
			task.spawn(entry.fn, ...)
		end
	end
	local waiting = self.waiting
	self.waiting = {}
	for _, thread in waiting do
		task.spawn(thread, ...)
	end
end

function Signal:Wait()
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end

Mock.Signal = Signal

-- Instances -------------------------------------------------------------------

local Instance = {}

local methods = {}

function methods.FindFirstChild(self, name)
	for _, child in rawget(self, "_children") do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function methods.WaitForChild(self, name, timeout)
	local deadline = os.clock() + (timeout or 5)
	while os.clock() < deadline do
		local child = methods.FindFirstChild(self, name)
		if child then
			return child
		end
		task.wait(0.01)
	end
	return nil
end

function methods.GetChildren(self)
	return table.clone(rawget(self, "_children"))
end

function methods.IsA(self, className)
	return className == "Instance" or rawget(self, "ClassName") == className
end

function methods.IsDescendantOf(self, ancestor)
	local parent = self.Parent
	while parent do
		if parent == ancestor then
			return true
		end
		parent = parent.Parent
	end
	return false
end

function methods.FireClient(self, player, ...)
	table.insert(rawget(self, "clientFires"), { player = player, args = table.pack(...) })
end

function methods.FireAllClients(self, ...)
	table.insert(rawget(self, "clientFires"), { player = "all", args = table.pack(...) })
end

local instanceMeta = {}

instanceMeta.__index = function(self, key)
	if key == "Parent" then
		return rawget(self, "_parent")
	end
	if methods[key] then
		return methods[key]
	end
	return methods.FindFirstChild(self, key)
end

instanceMeta.__newindex = function(self, key, value)
	if key == "Parent" then
		local old = rawget(self, "_parent")
		if old then
			local siblings = rawget(old, "_children")
			local index = table.find(siblings, self)
			if index then
				table.remove(siblings, index)
			end
		end
		rawset(self, "_parent", value)
		if value then
			table.insert(rawget(value, "_children"), self)
		end
		return
	end
	rawset(self, key, value)
end

instanceMeta.__tostring = function(self)
	return rawget(self, "Name")
end

function Instance.new(className, name)
	local inst = setmetatable({ ClassName = className, Name = name or className, _children = {} }, instanceMeta)
	if className == "RemoteEvent" then
		rawset(inst, "OnServerEvent", Signal.new())
		rawset(inst, "OnClientEvent", Signal.new())
		rawset(inst, "clientFires", {})
	end
	return inst
end

Mock.Instance = Instance

local function child(parent, className, name)
	local inst = Instance.new(className, name)
	inst.Parent = parent
	return inst
end

local function module(parent, name, path)
	local inst = child(parent, "ModuleScript", name)
	rawset(inst, "_path", path)
	return inst
end

-- Enum ------------------------------------------------------------------------

Mock.Enum = {
	ProductPurchaseDecision = {
		PurchaseGranted = "PurchaseGranted",
		NotProcessedYet = "NotProcessedYet",
	},
}

-- DataStore backend shared between worlds -------------------------------------

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[deepCopy(key)] = deepCopy(item)
	end
	return copy
end
Mock.deepCopy = deepCopy

function Mock.newBackend()
	return { stores = {}, failures = 0, latency = 0.02, passes = {}, writes = 0 }
end

local function newDataStore(backend, name)
	backend.stores[name] = backend.stores[name] or {}
	local data = backend.stores[name]
	local store = {}
	local function maybeFail()
		task.wait(backend.latency)
		if backend.failures > 0 then
			backend.failures -= 1
			error("502: simulated DataStore outage")
		end
	end
	function store.GetAsync(_, key)
		maybeFail()
		return deepCopy(data[key])
	end
	function store.UpdateAsync(_, key, transform)
		maybeFail()
		local result = transform(deepCopy(data[key]), nil)
		if result ~= nil then
			data[key] = deepCopy(result)
			backend.writes += 1
		end
		return deepCopy(result)
	end
	return store
end

-- World (one server) ----------------------------------------------------------

function Mock.newWorld(options)
	local backend = options.backend
	local templateRoot = options.templateRoot
	local world = { warnings = {}, kicks = {}, closeCallbacks = {}, name = options.name }

	local playersService = Instance.new("Players", "Players")
	rawset(playersService, "PlayerAdded", Signal.new())
	rawset(playersService, "PlayerRemoving", Signal.new())
	rawset(playersService, "GetPlayers", function()
		return methods.GetChildren(playersService)
	end)
	rawset(playersService, "GetPlayerByUserId", function(_, userId)
		for _, player in methods.GetChildren(playersService) do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end)

	local replicatedStorage = Instance.new("ReplicatedStorage", "ReplicatedStorage")
	local shared = child(replicatedStorage, "Folder", "Shared")
	module(shared, "Config", templateRoot .. "/src/shared/Config.luau")
	module(shared, "Guard", templateRoot .. "/src/shared/Guard.luau")
	module(shared, "Net", templateRoot .. "/src/shared/Net.luau")

	local serverScriptService = Instance.new("ServerScriptService", "ServerScriptService")
	local serverScript = child(serverScriptService, "Script", "Server")
	rawset(serverScript, "_path", templateRoot .. "/src/server/init.server.luau")
	local services = child(serverScript, "Folder", "Services")
	module(services, "DataService", templateRoot .. "/src/server/Services/DataService.luau")
	module(services, "PurchaseService", templateRoot .. "/src/server/Services/PurchaseService.luau")

	local guidCounter = 0
	local serviceMap = {
		Players = playersService,
		ReplicatedStorage = replicatedStorage,
		ServerScriptService = serverScriptService,
		DataStoreService = {
			GetDataStore = function(_, name)
				return newDataStore(backend, name)
			end,
		},
		RunService = {
			IsStudio = function()
				return options.studio == true
			end,
			IsServer = function()
				return true
			end,
		},
		HttpService = {
			GenerateGUID = function()
				guidCounter += 1
				return `{world.name}-guid-{guidCounter}`
			end,
		},
		MarketplaceService = {
			PromptGamePassPurchaseFinished = Signal.new(),
			UserOwnsGamePassAsync = function(_, userId, passId)
				task.wait(0.01)
				return backend.passes[`{userId}:{passId}`] == true
			end,
		},
	}
	world.services = serviceMap

	local game = {
		JobId = options.jobId or "",
		GetService = function(_, name)
			return assert(serviceMap[name], `mock has no service {name}`)
		end,
		BindToClose = function(_, callback)
			table.insert(world.closeCallbacks, callback)
		end,
	}
	world.game = game

	local cache = {}
	local function load(scriptInstance)
		local source = fs.readFile(rawget(scriptInstance, "_path"))
		local chunk = luau.load(source, {
			debugName = `{world.name}:{scriptInstance.Name}`,
			environment = {
				game = game,
				script = scriptInstance,
				require = world.require,
				Instance = Instance,
				Enum = Mock.Enum,
				task = task,
				warn = function(...)
					local message = table.concat(table.pack(...) :: any, " ")
					table.insert(world.warnings, message)
					print(`    [{world.name} warn] {message}`)
				end,
			},
		})
		return chunk()
	end

	function world.require(moduleInstance)
		if cache[moduleInstance] == nil then
			cache[moduleInstance] = load(moduleInstance)
		end
		return cache[moduleInstance]
	end

	function world.boot()
		load(serverScript)
	end

	function world.module(name)
		local found = methods.FindFirstChild(shared, name) or methods.FindFirstChild(services, name)
		return world.require(found)
	end

	function world.remote(name)
		return replicatedStorage.Remotes:FindFirstChild(name)
	end

	function world.join(userId)
		local player = Instance.new("Player", `Player{userId}`)
		rawset(player, "UserId", userId)
		rawset(player, "Kick", function(self, message)
			table.insert(world.kicks, { userId = userId, message = message })
			world.leave(self)
		end)
		player.Parent = playersService
		playersService.PlayerAdded:Fire(player)
		return player
	end

	function world.leave(player)
		if player.Parent then
			player.Parent = nil
			playersService.PlayerRemoving:Fire(player)
		end
	end

	-- Roblox runs BindToClose callbacks in parallel and waits for all of them.
	function world.shutdown()
		local pending = #world.closeCallbacks
		for _, callback in world.closeCallbacks do
			task.spawn(function()
				callback()
				pending -= 1
			end)
		end
		for _, player in methods.GetChildren(playersService) do
			world.leave(player)
		end
		while pending > 0 do
			task.wait(0.01)
		end
	end

	return world
end

return Mock
