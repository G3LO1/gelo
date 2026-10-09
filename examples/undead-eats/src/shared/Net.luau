-- One place for every remote. The server creates them (Net.setup), validates and
-- rate-limits every client call; the client only fires intents.
--
-- Server: Net.handle("BuyItem", { Guard.oneOf(itemIds) }, function(player, itemId) ... end)
-- Client: Net.fire("BuyItem", "Sword")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Guard = require(script.Parent.Guard)

local Net = {}

-- Add a name here before using it on either side.
Net.Events = { "DataSync", "DropItem", "Notify", "RunResult" } -- RemoteEvents
Net.Functions = { "GetData", "BuyUpgrade" } -- RemoteFunctions, client -> server only (never InvokeClient)

type Options = { rate: number?, burst: number? }

local FOLDER_NAME = "Remotes"
local DEFAULT_RATE = 10 -- calls per second per player per remote
local IS_SERVER = RunService:IsServer()

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	local found = if IS_SERVER
		then ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		else ReplicatedStorage:WaitForChild(FOLDER_NAME)
	if not found then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		found = created
	end
	folder = found :: Folder
	return folder :: Folder
end

local function getRemote(name: string, className: string): any
	local remotes = getFolder()
	local remote = if IS_SERVER then remotes:FindFirstChild(name) else remotes:WaitForChild(name, 10)
	assert(
		remote and remote:IsA(className),
		`Remote "{name}" ({className}) is missing: add it to Net.Events or Net.Functions`
	)
	return remote
end

-- Token bucket per player per remote.
local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}

local function allow(player: Player, name: string, rate: number, burst: number): boolean
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local now = os.clock()
	local bucket = playerBuckets[name]
	if not bucket then
		bucket = { tokens = burst, last = now }
		playerBuckets[name] = bucket
	end
	bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.last) * rate)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

local function argsValid(validators: { Guard.Check }, ...: any): boolean
	if select("#", ...) > #validators then
		return false
	end
	for index, check in validators do
		if not check((select(index, ...))) then
			return false
		end
	end
	return true
end

local function limits(options: Options?): (number, number)
	local rate = options and options.rate or DEFAULT_RATE
	local burst = options and options.burst or math.max(rate, 1)
	return rate, burst
end

-- Server ----------------------------------------------------------------------

function Net.setup()
	assert(IS_SERVER, "Net.setup is server-only")
	local remotes = getFolder()
	for _, name in Net.Events do
		if not remotes:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = remotes
		end
	end
	for _, name in Net.Functions do
		if not remotes:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = remotes
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

-- Rejected calls (bad arguments, too many calls) are dropped silently.
function Net.handle(name: string, validators: { Guard.Check }, handler: (Player, ...any) -> (), options: Options?)
	local remote = getRemote(name, "RemoteEvent")
	local rate, burst = limits(options)
	remote.OnServerEvent:Connect(function(player: Player, ...)
		if allow(player, name, rate, burst) and argsValid(validators, ...) then
			handler(player, ...)
		end
	end)
end

-- Rejected calls return nil to the client.
function Net.handleInvoke(
	name: string,
	validators: { Guard.Check },
	handler: (Player, ...any) -> ...any,
	options: Options?
)
	local remote = getRemote(name, "RemoteFunction")
	local rate, burst = limits(options)
	remote.OnServerInvoke = function(player: Player, ...)
		if allow(player, name, rate, burst) and argsValid(validators, ...) then
			return handler(player, ...)
		end
		return nil
	end
end

function Net.fireClient(player: Player, name: string, ...: any)
	getRemote(name, "RemoteEvent"):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	getRemote(name, "RemoteEvent"):FireAllClients(...)
end

-- Client ----------------------------------------------------------------------

function Net.fire(name: string, ...: any)
	getRemote(name, "RemoteEvent"):FireServer(...)
end

function Net.invoke(name: string, ...: any): ...any
	return getRemote(name, "RemoteFunction"):InvokeServer(...)
end

function Net.on(name: string, handler: (...any) -> ()): RBXScriptConnection
	return getRemote(name, "RemoteEvent").OnClientEvent:Connect(handler)
end

return Net
