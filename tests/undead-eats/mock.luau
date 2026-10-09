-- Roblox engine mock for client + server integration tests of examples/undead-eats under Lune.
-- One server world; client controllers run in a second environment (own module cache,
-- RunService:IsServer() == false) that shares the instance tree, like a replicated client.
-- Roblox datatypes (UDim2, Color3, Enum, TweenInfo...) come from @lune/roblox.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
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

local BUTTONS = { TextButton = true, ImageButton = true }
local methods = {}
local Instance = {}
local instanceMeta = {}

function methods.FindFirstChild(self, name)
	for _, child in rawget(self, "_children") do
		if rawget(child, "Name") == name then
			return child
		end
	end
	return nil
end

function methods.WaitForChild(self, name, timeout)
	local deadline = os.clock() + (timeout or 5)
	repeat
		local child = methods.FindFirstChild(self, name)
		if child then
			return child
		end
		task.wait(0.01)
	until os.clock() > deadline
	return nil
end

function methods.GetChildren(self)
	return table.clone(rawget(self, "_children"))
end

function methods.IsA(self, className)
	return className == "Instance" or rawget(self, "ClassName") == className
end

function methods.IsDescendantOf(self, ancestor)
	local parent = rawget(self, "_parent")
	while parent do
		if parent == ancestor then
			return true
		end
		parent = rawget(parent, "_parent")
	end
	return false
end

function methods.GetFullName(self)
	local parts = {}
	local current = self
	while current do
		table.insert(parts, 1, rawget(current, "Name"))
		current = rawget(current, "_parent")
	end
	return table.concat(parts, ".")
end

function methods.SetAttribute(self, name, value)
	local attributes = rawget(self, "_attributes")
	if attributes[name] ~= value then
		attributes[name] = value
		local signal = rawget(self, "_attributeSignals")[name]
		if signal then
			signal:Fire()
		end
	end
end

function methods.GetAttribute(self, name)
	return rawget(self, "_attributes")[name]
end

function methods.GetAttributeChangedSignal(self, name)
	local signals = rawget(self, "_attributeSignals")
	signals[name] = signals[name] or Signal.new()
	return signals[name]
end

function methods.AddTag() end

function methods.GetServerTimeNow()
	return os.clock()
end

function methods.FireClient(self, player, ...)
	table.insert(rawget(self, "clientFires"), { player = player, args = table.pack(...) })
	if player == Mock.activePlayer then
		rawget(self, "OnClientEvent"):Fire(...)
	end
end

function methods.FireAllClients(self, ...)
	table.insert(rawget(self, "clientFires"), { player = "all", args = table.pack(...) })
	rawget(self, "OnClientEvent"):Fire(...)
end

function methods.FireServer(self, ...)
	rawget(self, "OnServerEvent"):Fire(Mock.activePlayer, ...)
end

function methods.InvokeServer(self, ...)
	local callback = rawget(self, "OnServerInvoke")
	assert(callback, `{rawget(self, "Name")} has no OnServerInvoke`)
	task.wait() -- a network round trip yields
	return callback(Mock.activePlayer, ...)
end

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
	local inst = setmetatable({
		ClassName = className,
		Name = name or className,
		_children = {},
		_attributes = {},
		_attributeSignals = {},
	}, instanceMeta)
	if className == "RemoteEvent" then
		rawset(inst, "OnServerEvent", Signal.new())
		rawset(inst, "OnClientEvent", Signal.new())
		rawset(inst, "clientFires", {})
	end
	if BUTTONS[className] then
		rawset(inst, "Activated", Signal.new())
	end
	return inst
end

Mock.Instance = Instance

-- UI from ui-spec.json ----------------------------------------------------------

local function hex(value)
	local r, g, b = string.match(value, "^#(%x%x)(%x%x)(%x%x)$")
	return roblox.Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
end

local function decode(spec, value)
	if type(value) ~= "table" then
		return value
	end
	if value.udim2 then
		local v = value.udim2
		return roblox.UDim2.new(v[1], v[2], v[3], v[4])
	elseif value.udim then
		return roblox.UDim.new(value.udim[1], value.udim[2])
	elseif value.vector2 then
		return roblox.Vector2.new(value.vector2[1], value.vector2[2])
	elseif value.color then
		return hex(value.color)
	elseif value.token then
		return decode(spec, spec.tokens[value.token])
	elseif value.enum then
		local enumName, item = string.match(value.enum, "^(%w+)%.(%w+)$")
		return roblox.Enum[enumName][item]
	elseif value.image then
		return spec.images[value.image]
	end
	return value -- fonts, sequences, rects: not needed by the controllers
end

local function buildNode(spec, node, parent)
	local inst = Instance.new(node.class, node.name)
	for prop, value in node.props or {} do
		inst[prop] = decode(spec, value)
	end
	for name, value in node.attributes or {} do
		methods.SetAttribute(inst, name, decode(spec, value))
	end
	for _, child in node.children or {} do
		buildNode(spec, child, inst)
	end
	inst.Parent = parent
	return inst
end

function Mock.buildUi(specPath, parent)
	local spec = serde.decode("json", fs.readFile(specPath))
	for _, screen in spec.screens do
		buildNode(spec, screen, parent)
	end
end

-- Project loading ---------------------------------------------------------------

local function mountFolder(dir, parent)
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			local folder = Instance.new("Folder", entry)
			folder.Parent = parent
			mountFolder(path, folder)
		elseif string.match(entry, "%.luau$") and not string.match(entry, "^init%.") then
			local module = Instance.new("ModuleScript", (string.gsub(entry, "%.luau$", "")))
			rawset(module, "_path", path)
			module.Parent = parent
		end
	end
end

-- DataStore backend ---------------------------------------------------------------

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

local function newDataStore(data)
	local store = {}
	function store.GetAsync(_, key)
		task.wait()
		return deepCopy(data[key])
	end
	function store.UpdateAsync(_, key, transform)
		task.wait()
		local result = transform(deepCopy(data[key]), nil)
		if result ~= nil then
			data[key] = deepCopy(result)
		end
		return deepCopy(result)
	end
	return store
end

-- World -------------------------------------------------------------------------

function Mock.newWorld(projectRoot)
	local world = { warnings = {}, analytics = {}, kicks = {} }

	local workspaceInst = Instance.new("Workspace", "Workspace")
	local players = Instance.new("Players", "Players")
	rawset(players, "PlayerAdded", Signal.new())
	rawset(players, "PlayerRemoving", Signal.new())
	rawset(players, "GetPlayers", function()
		return methods.GetChildren(players)
	end)
	rawset(players, "GetPlayerByUserId", function(_, userId)
		for _, player in methods.GetChildren(players) do
			if rawget(player, "UserId") == userId then
				return player
			end
		end
		return nil
	end)

	local replicatedStorage = Instance.new("ReplicatedStorage", "ReplicatedStorage")
	local shared = Instance.new("Folder", "Shared")
	shared.Parent = replicatedStorage
	mountFolder(`{projectRoot}/src/shared`, shared)

	local serverScriptService = Instance.new("ServerScriptService", "ServerScriptService")
	local server = Instance.new("Script", "Server")
	server.Parent = serverScriptService
	mountFolder(`{projectRoot}/src/server`, server)

	local starterPlayerScripts = Instance.new("StarterPlayerScripts", "StarterPlayerScripts")
	local client = Instance.new("LocalScript", "Client")
	client.Parent = starterPlayerScripts
	mountFolder(`{projectRoot}/src/client`, client)

	local stores = {}
	local guidCounter = 0
	local closeCallbacks = {}

	local function warnFn(...)
		local message = table.concat(table.pack(...) :: any, " ")
		table.insert(world.warnings, message)
		print(`    [warn] {message}`)
	end

	local baseServices = {
		Players = players,
		ReplicatedStorage = replicatedStorage,
		ServerScriptService = serverScriptService,
		Workspace = workspaceInst,
		DataStoreService = {
			GetDataStore = function(_, name)
				stores[name] = stores[name] or {}
				return newDataStore(stores[name])
			end,
		},
		HttpService = {
			GenerateGUID = function()
				guidCounter += 1
				return `guid-{guidCounter}`
			end,
		},
		AnalyticsService = {
			LogEconomyEvent = function(_, player, flow, currency, amount, balance, txType, sku)
				table.insert(world.analytics, {
					player = player,
					flow = flow,
					currency = currency,
					amount = amount,
					balance = balance,
					txType = txType,
					sku = sku,
				})
			end,
		},
		TweenService = {
			Create = function(_, inst, _info, goals)
				local tween = { Completed = Signal.new() }
				function tween.Play()
					for prop, value in goals do
						inst[prop] = value
					end
					tween.Completed:Fire(roblox.Enum.PlaybackState.Completed)
				end
				function tween.Cancel() end
				return tween
			end,
		},
		GuiService = { SelectedObject = nil },
		UserInputService = { GamepadEnabled = false, TouchEnabled = false },
	}

	local function makeGame(isServer)
		local services = setmetatable({
			RunService = {
				IsServer = function()
					return isServer
				end,
				IsClient = function()
					return not isServer
				end,
				IsStudio = function()
					return false
				end,
			},
		}, { __index = baseServices })
		return {
			JobId = "job-test",
			GetService = function(_, name)
				return assert(services[name], `mock has no service {name}`)
			end,
			BindToClose = function(_, callback)
				table.insert(closeCallbacks, callback)
			end,
		}
	end

	local function newRuntime(isServer)
		local runtime = { cache = {}, game = makeGame(isServer) }
		function runtime.require(moduleInstance)
			assert(moduleInstance, "require(nil)")
			if runtime.cache[moduleInstance] == nil then
				local chunk = luau.load(fs.readFile(rawget(moduleInstance, "_path")), {
					debugName = methods.GetFullName(moduleInstance),
					environment = {
						game = runtime.game,
						workspace = workspaceInst,
						script = moduleInstance,
						require = runtime.require,
						Instance = Instance,
						Enum = roblox.Enum,
						UDim = roblox.UDim,
						UDim2 = roblox.UDim2,
						Color3 = roblox.Color3,
						Vector2 = roblox.Vector2,
						Vector3 = roblox.Vector3,
						CFrame = roblox.CFrame,
						TweenInfo = roblox.TweenInfo or {
							new = function(...)
								return table.pack(...)
							end,
						}, -- not in @lune/roblox
						task = task,
						warn = warnFn,
					},
				})
				runtime.cache[moduleInstance] = chunk()
			end
			return runtime.cache[moduleInstance]
		end
		return runtime
	end

	world.workspace = workspaceInst
	world.services = baseServices
	world.server = newRuntime(true)
	world.client = newRuntime(false)

	-- Require a server or client module by path, e.g. world.serverModule("Services/GameService").
	local function byPath(root, path)
		local current = root
		for part in string.gmatch(path, "[^/]+") do
			current = methods.FindFirstChild(current, part)
			assert(current, `module {path} not found`)
		end
		return current
	end
	function world.serverModule(path)
		return world.server.require(byPath(server, path))
	end
	function world.sharedModule(name)
		return world.server.require(byPath(shared, name))
	end
	function world.clientShared(name)
		return world.client.require(byPath(shared, name))
	end
	function world.clientModule(path)
		return world.client.require(byPath(client, path))
	end

	function world.remote(name)
		return methods.FindFirstChild(methods.FindFirstChild(replicatedStorage, "Remotes"), name)
	end

	function world.join(userId, uiSpecPath)
		local player = Instance.new("Player", `Player{userId}`)
		rawset(player, "UserId", userId)
		rawset(player, "Kick", function(self, message)
			table.insert(world.kicks, message)
			world.leave(self)
		end)
		local playerGui = Instance.new("PlayerGui", "PlayerGui")
		playerGui.Parent = player
		if uiSpecPath then
			Mock.buildUi(uiSpecPath, playerGui)
		end
		player.Parent = players
		rawset(players, "LocalPlayer", player)
		Mock.activePlayer = player
		players.PlayerAdded:Fire(player)
		return player
	end

	function world.leave(player)
		if rawget(player, "_parent") then
			player.Parent = nil
			players.PlayerRemoving:Fire(player)
		end
	end

	return world
end

return Mock
