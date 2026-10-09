-- Behaviour tests for the roblox-luau-codegen template (DataService, PurchaseService, Net, Guard).
-- Run from the repo root: lune run tests/roblox-luau-codegen/run

local process = require("@lune/process")
local task = require("@lune/task")

local Mock = require("./mock")

local TEMPLATE = "plugins/roblox-studio/skills/roblox-luau-codegen/assets/template"
local KEY_PREFIX = "Player_"
local STORE = "PlayerData_v1"

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
	local deadline = os.clock() + (timeout or 10)
	while os.clock() < deadline do
		if predicate() then
			return true
		end
		task.wait(0.02)
	end
	return false
end

local function record(backend, userId: number)
	return backend.stores[STORE] and backend.stores[STORE][KEY_PREFIX .. userId]
end

local function newServer(backend, name: string, options: any?)
	local world = Mock.newWorld({
		backend = backend,
		templateRoot = TEMPLATE,
		jobId = `job-{name}`,
		name = name,
		studio = options and options.studio,
	})
	world.boot()
	local config = world.module("Config")
	config.Data.LoadRetries = (options and options.loadRetries) or 3
	return world
end

local function test(name: string, body: () -> ())
	print(name)
	local ok, err = pcall(body)
	if not ok then
		failed += 1
		print(`  FAIL error: {err}`)
	end
end

test("new player gets defaults, a lock, and a client sync", function()
	local backend = Mock.newBackend()
	local server = newServer(backend, "A")
	local DataService = server.module("DataService")
	local player = server.join(1)
	local data = DataService.WaitFor(player, 5)
	check(data ~= nil and data.Coins == 0, "default data loaded")
	check(record(backend, 1).Lock.ServerId == "job-A", "lock owned by server A")
	local fires = server.remote("DataSync").clientFires
	check(#fires >= 1 and fires[1].player == player, "DataSync sent to the player")
	check(server.remote("GetData").OnServerInvoke(player).Coins == 0, "GetData returns the profile")
end)

test("updates save and leaving releases the lock", function()
	local backend = Mock.newBackend()
	local server = newServer(backend, "A")
	local DataService = server.module("DataService")
	local player = server.join(2)
	DataService.WaitFor(player, 5)
	DataService.Update(player, function(data)
		data.Coins += 250
	end)
	check(DataService.Save(player), "Save returns true")
	check(record(backend, 2).Data.Coins == 250, "coins written to the store")
	server.leave(player)
	check(waitUntil(function()
		return record(backend, 2).Lock == nil
	end, 5), "lock released on leave")
	check(DataService.Get(player) == nil, "profile dropped after leave")
end)

test("server hop: B waits for A to release, then gets A's latest data", function()
	local backend = Mock.newBackend()
	local serverA = newServer(backend, "A")
	local serverB = newServer(backend, "B")
	local dataA = serverA.module("DataService")
	local dataB = serverB.module("DataService")
	local playerA = serverA.join(3)
	dataA.WaitFor(playerA, 5)
	dataA.Update(playerA, function(data)
		data.Coins = 777
	end)
	-- Player joins B while A still holds the session (teleport race), A releases a moment later.
	local playerB = serverB.join(3)
	task.delay(0.5, serverA.leave, playerA)
	local loaded = dataB.WaitFor(playerB, 10)
	check(loaded ~= nil and loaded.Coins == 777, "B loaded the coins saved by A")
	check(record(backend, 3).Lock.ServerId == "job-B", "lock moved to B")
	check(#serverB.kicks == 0, "nobody kicked")
end)

test("lock held by a live server: B gives up and kicks instead of loading stale data", function()
	local backend = Mock.newBackend()
	local serverA = newServer(backend, "A")
	local serverB = newServer(backend, "B", { loadRetries = 2 })
	local playerA = serverA.join(4)
	serverA.module("DataService").WaitFor(playerA, 5)
	serverB.join(4)
	check(waitUntil(function()
		return #serverB.kicks == 1
	end, 12), "B kicked the player after retries")
	check(record(backend, 4).Lock.ServerId == "job-A", "A keeps the lock")
end)

test("stale lock from a crashed server is taken over; the old server stops writing", function()
	local backend = Mock.newBackend()
	local serverA = newServer(backend, "A")
	local dataA = serverA.module("DataService")
	local playerA = serverA.join(5)
	dataA.WaitFor(playerA, 5)
	dataA.Update(playerA, function(data)
		data.Coins = 10
	end)
	dataA.Save(playerA)
	record(backend, 5).Lock.Time -= 3600 -- A looks crashed: lock not refreshed for an hour
	local serverB = newServer(backend, "B")
	local dataB = serverB.module("DataService")
	local playerB = serverB.join(5)
	local loaded = dataB.WaitFor(playerB, 5)
	check(loaded ~= nil and loaded.Coins == 10, "B took over the stale lock")
	dataB.Update(playerB, function(data)
		data.Coins = 99
	end)
	dataB.Save(playerB)
	dataA.Update(playerA, function(data)
		data.Coins = -1
	end)
	check(dataA.Save(playerA) == false, "A's save is refused")
	check(record(backend, 5).Data.Coins == 99, "B's data was not overwritten")
	check(#serverA.kicks == 1, "A kicked its stale session")
end)

test("migrations and new default fields apply on load", function()
	local backend = Mock.newBackend()
	backend.stores[STORE] = {
		[KEY_PREFIX .. 6] = { Data = { Version = 1, Coins = 5, Inventory = {}, PurchaseHistory = {} } },
	}
	local server = newServer(backend, "A")
	local config = server.module("Config")
	config.Data.Version = 2
	config.Data.Migrations[2] = function(data)
		data.Gems = data.Coins * 2
	end
	config.DefaultData.Settings = { Music = true }
	local player = server.join(6)
	local data = server.module("DataService").WaitFor(player, 5)
	check(data.Version == 2 and data.Gems == 10, "migration 2 ran")
	check(data.Settings and data.Settings.Music == true, "new default field filled in")
	check(data.Coins == 5, "existing data kept")
end)

test("load survives a short DataStore outage", function()
	local backend = Mock.newBackend()
	local server = newServer(backend, "A")
	backend.failures = 1
	local player = server.join(7)
	local data = server.module("DataService").WaitFor(player, 10)
	check(data ~= nil, "loaded after a retry")
	check(#server.kicks == 0, "not kicked")
end)

test("developer product: granted once, saved, idempotent on retry", function()
	local backend = Mock.newBackend()
	local server = newServer(backend, "A")
	local DataService = server.module("DataService")
	local PurchaseService = server.module("PurchaseService")
	local Marketplace = server.services.MarketplaceService
	PurchaseService.RegisterProduct(1001, function(_player, data)
		data.Coins += 100
	end)
	local player = server.join(8)
	DataService.WaitFor(player, 5)
	local receipt = { PlayerId = 8, ProductId = 1001, PurchaseId = "p-1" }
	check(Marketplace.ProcessReceipt(receipt) == "PurchaseGranted", "first receipt granted")
	check(DataService.Get(player).Coins == 100, "coins granted")
	check(record(backend, 8).Data.Coins == 100, "grant saved before acknowledging")
	check(Marketplace.ProcessReceipt(receipt) == "PurchaseGranted", "retried receipt acknowledged")
	check(DataService.Get(player).Coins == 100, "not granted twice")
end)

test("developer product: save failure defers acknowledgement without double grant", function()
	local backend = Mock.newBackend()
	local server = newServer(backend, "A")
	local DataService = server.module("DataService")
	local PurchaseService = server.module("PurchaseService")
	local Marketplace = server.services.MarketplaceService
	PurchaseService.RegisterProduct(1002, function(_player, data)
		data.Coins += 50
	end)
	local player = server.join(9)
	DataService.WaitFor(player, 5)
	local receipt = { PlayerId = 9, ProductId = 1002, PurchaseId = "p-2" }
	backend.failures = 1
	check(Marketplace.ProcessReceipt(receipt) == "NotProcessedYet", "not acknowledged while the save failed")
	check(Marketplace.ProcessReceipt(receipt) == "PurchaseGranted", "acknowledged on Roblox's retry")
	check(DataService.Get(player).Coins == 50, "granted exactly once")
	check(Marketplace.ProcessReceipt({ PlayerId = 404, ProductId = 1002, PurchaseId = "p-3" }) == "NotProcessedYet",
		"player not in server -> NotProcessedYet")
	check(Marketplace.ProcessReceipt({ PlayerId = 9, ProductId = 9999, PurchaseId = "p-4" }) == "NotProcessedYet",
		"unknown product -> NotProcessedYet")
end)

test("pass ownership is cached and updated after purchase", function()
	local backend = Mock.newBackend()
	local server = newServer(backend, "A")
	local PurchaseService = server.module("PurchaseService")
	local player = server.join(10)
	check(PurchaseService.OwnsPass(player, 55) == false, "does not own pass yet")
	local notified = false
	PurchaseService.OnPassPurchased(function(_, passId)
		notified = passId == 55
	end)
	server.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(player, 55, true)
	task.wait(0.05)
	check(PurchaseService.OwnsPass(player, 55) == true, "owns pass after purchase (cache updated)")
	check(notified, "OnPassPurchased fired")
end)

test("shutdown saves and releases every player", function()
	local backend = Mock.newBackend()
	local server = newServer(backend, "A")
	local DataService = server.module("DataService")
	local players = {}
	for userId = 11, 13 do
		local player = server.join(userId)
		DataService.WaitFor(player, 5)
		DataService.Update(player, function(data)
			data.Coins = userId
		end)
		table.insert(players, player)
	end
	server.shutdown()
	local allSaved = true
	for userId = 11, 13 do
		local stored = record(backend, userId)
		allSaved = allSaved and stored.Data.Coins == userId and stored.Lock == nil
	end
	check(allSaved, "all 3 players saved with locks released before shutdown finished")
end)

test("Studio without API access falls back to the in-memory store", function()
	local backend = Mock.newBackend()
	backend.failures = 1 -- the probe GetAsync fails like "StudioAccessToApisNotAllowed"
	local server = newServer(backend, "S", { studio = true })
	local player = server.join(14)
	local data = server.module("DataService").WaitFor(player, 5)
	check(data ~= nil, "data available in Studio mock mode")
	check(record(backend, 14) == nil, "nothing written to the real store")
end)

test("Net: argument validation", function()
	local backend = Mock.newBackend()
	local server = newServer(backend, "A")
	local Net = server.module("Net")
	local Guard = server.module("Guard")
	table.insert(Net.Events, "TestEvent")
	Net.setup()
	local calls = 0
	-- High rate so only validation can reject here.
	Net.handle("TestEvent", { Guard.integer(1, 10), Guard.optional(Guard.string(5)) }, function()
		calls += 1
	end, { rate = 1000, burst = 1000 })
	local player = server.join(15)
	local remote = server.remote("TestEvent")
	local function fire(...)
		remote.OnServerEvent:Fire(player, ...)
		task.wait()
	end
	fire(3)
	fire(3, "hey")
	check(calls == 2, "valid calls accepted")
	fire(0 / 0)
	fire(math.huge)
	fire(2.5)
	fire("3")
	fire(11)
	fire(3, "too long string")
	fire(3, "ok", "extra")
	fire()
	check(calls == 2, "NaN, inf, fractions, wrong types, out of range, long strings, extra and missing args rejected")
	fire(10, nil)
	check(calls == 3, "optional argument may be nil")
end)

test("Net: rate limiting per player", function()
	local backend = Mock.newBackend()
	local server = newServer(backend, "A")
	local Net = server.module("Net")
	local Guard = server.module("Guard")
	table.insert(Net.Events, "LimitedEvent")
	Net.setup()
	local calls = {}
	Net.handle("LimitedEvent", { Guard.integer() }, function(player)
		calls[player] = (calls[player] or 0) + 1
	end, { rate = 5, burst = 5 })
	local spammer = server.join(16)
	local normal = server.join(17)
	local remote = server.remote("LimitedEvent")
	for _ = 1, 50 do
		remote.OnServerEvent:Fire(spammer, 1)
	end
	remote.OnServerEvent:Fire(normal, 1)
	task.wait(0.05)
	check(calls[spammer] == 5, `spammer limited to the burst of 5 (got {calls[spammer]})`)
	check(calls[normal] == 1, "other players unaffected")
	task.wait(1)
	remote.OnServerEvent:Fire(spammer, 1)
	task.wait(0.05)
	check(calls[spammer] == 6, "tokens refill over time")
end)

test("Guard validators", function()
	local server = newServer(Mock.newBackend(), "A")
	local Guard = server.module("Guard")
	check(Guard.number(0, 10)(5) and not Guard.number(0, 10)(11), "number range")
	check(not Guard.number()(0 / 0) and not Guard.number()(-math.huge), "number rejects NaN/inf")
	check(Guard.oneOf({ "Sword" })("Sword") and not Guard.oneOf({ "Sword" })("Axe"), "oneOf")
	local arr = Guard.array(Guard.integer(), 3)
	check(arr({ 1, 2 }) and not arr({ 1, 2, 3, 4 }) and not arr({ x = 1 }) and not arr({ 1, "a" }), "array")
	check(not Guard.string(10)("\255\254"), "string rejects invalid UTF-8")
end)

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
