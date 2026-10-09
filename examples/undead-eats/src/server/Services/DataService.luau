-- Player data with session locking: only the server that holds a player's lock may
-- write their data, which prevents duplication and rollbacks when players hop servers.
--
-- DataService.Get(player)            -> data table or nil while loading
-- DataService.WaitFor(player, 15)    -> data table or nil on timeout / player left
-- DataService.Update(player, fn)     -> mutate data inside fn; syncs to the client
-- DataService.Save(player)           -> true when written (autosave runs on its own)
-- DataService.OnChanged(callback)    -> callback(player, data) after load and every Update

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local DataService = {}

type Profile = { Data: any, Saving: boolean, LockLost: boolean }

local settings = Config.Data
local SERVER_ID = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

local store: DataStore? = nil
local mockStore: { [string]: any } = {}
local profiles: { [Player]: Profile } = {}
local releasing: { [number]: boolean } = {} -- UserIds whose lock is being released
local activeSaves = 0
local changedCallbacks: { (Player, any) -> () } = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[deepCopy(key)] = deepCopy(item)
	end
	return copy
end

-- Fill in fields that were added to DefaultData after the player last saved.
local function reconcile(data: any, defaults: any)
	for key, default in defaults do
		if data[key] == nil then
			data[key] = deepCopy(default)
		elseif type(default) == "table" and type(data[key]) == "table" then
			reconcile(data[key], default)
		end
	end
end

local function migrate(data: any)
	local version = data.Version or 1
	while version < settings.Version do
		version += 1
		local migration = settings.Migrations[version]
		if migration then
			migration(data)
		end
		data.Version = version
	end
end

local function keyFor(player: Player): string
	return settings.KeyPrefix .. player.UserId
end

-- UpdateAsync with a mock fallback. transform returns nil to cancel the write.
local function update(key: string, transform: (any) -> any): (boolean, string?)
	local dataStore = store
	if dataStore then
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key, transform)
		end)
		return ok, if ok then nil else tostring(err)
	end
	local result = transform(deepCopy(mockStore[key]))
	if result ~= nil then
		mockStore[key] = deepCopy(result)
	end
	return true, nil
end

local function notifyChanged(player: Player, data: any)
	Net.fireClient(player, "DataSync", data)
	for _, callback in changedCallbacks do
		task.spawn(callback, player, data)
	end
end

local function loadData(player: Player): any
	local key = keyFor(player)
	-- Rejoined this same server while the previous session was still releasing.
	while releasing[player.UserId] and player.Parent do
		task.wait(0.1)
	end
	for attempt = 1, settings.LoadRetries do
		local acquired = false
		local loaded = nil
		local ok, err = update(key, function(old)
			acquired = false
			local now = os.time()
			local record = if type(old) == "table" then old else {}
			local lock = record.Lock
			if lock and lock.ServerId ~= SERVER_ID and now - (lock.Time or 0) < settings.LockExpireSeconds then
				return nil -- another server still owns this player's data
			end
			if type(record.Data) ~= "table" then
				record.Data = deepCopy(Config.DefaultData)
			end
			record.Lock = { ServerId = SERVER_ID, Time = now }
			acquired = true
			loaded = record.Data
			return record
		end)
		if ok and acquired then
			return loaded
		end
		if not ok then
			warn(`[DataService] Load attempt {attempt} failed for {player.UserId}: {err}`)
		end
		if player.Parent == nil then
			return nil
		end
		task.wait(2 * attempt)
	end
	return nil
end

-- Writes the profile's data; release = true also drops the lock (player left / server closing).
local function saveProfile(player: Player, profile: Profile, release: boolean): boolean
	if profile.LockLost then
		return false
	end
	activeSaves += 1 -- counted before waiting so BindToClose never sees a gap
	while profile.Saving do
		task.wait()
	end
	profile.Saving = true
	local snapshot = deepCopy(profile.Data)
	local wrote = false
	local ok, err = update(keyFor(player), function(old)
		wrote = false
		if type(old) ~= "table" or not old.Lock or old.Lock.ServerId ~= SERVER_ID then
			return nil -- lock was taken over: never overwrite the newer session
		end
		old.Data = snapshot
		old.Lock = if release then nil else { ServerId = SERVER_ID, Time = os.time() }
		wrote = true
		return old
	end)
	profile.Saving = false
	activeSaves -= 1
	if not ok then
		warn(`[DataService] Save failed for {player.UserId}: {err}`)
		return false
	end
	if not wrote then
		profile.LockLost = true
		warn(`[DataService] Lost the session lock for {player.UserId}; data not saved here`)
		if player.Parent then
			player:Kick("Your data was opened on another server. Please rejoin.")
		end
	end
	return wrote
end

-- Final save + unlock. The profile is removed first so no autosave or Update touches it again.
local function releaseProfile(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profiles[player] = nil
	releasing[player.UserId] = true
	saveProfile(player, profile, true)
	releasing[player.UserId] = nil
end

local function onPlayerAdded(player: Player)
	local data = loadData(player)
	if not data then
		if player.Parent then
			player:Kick("Could not load your data. Please rejoin in a moment.")
		end
		return
	end
	migrate(data)
	reconcile(data, Config.DefaultData)
	profiles[player] = { Data = data, Saving = false, LockLost = false }
	if player.Parent == nil then
		-- Left while loading: release the lock straight away.
		releaseProfile(player)
		return
	end
	notifyChanged(player, data)
end

function DataService.Get(player: Player): any
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function DataService.WaitFor(player: Player, timeout: number?): any
	local deadline = os.clock() + (timeout or 15)
	while not profiles[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return DataService.Get(player)
end

-- fn must not yield. Returns false if the player's data is not loaded.
function DataService.Update(player: Player, fn: (data: any) -> ()): boolean
	local data = DataService.Get(player)
	if not data then
		return false
	end
	fn(data)
	notifyChanged(player, data)
	return true
end

function DataService.Save(player: Player): boolean
	local profile = profiles[player]
	return if profile then saveProfile(player, profile, false) else false
end

function DataService.OnChanged(callback: (Player, any) -> ())
	table.insert(changedCallbacks, callback)
end

function DataService.Init()
	local dataStore = DataStoreService:GetDataStore(settings.StoreName)
	store = dataStore
	if RunService:IsStudio() and settings.UseMockInStudio then
		local ok = pcall(function()
			dataStore:GetAsync("__probe")
		end)
		if not ok then
			store = nil
			warn("[DataService] DataStores unavailable in Studio: using an in-memory store (nothing is saved).")
		end
	end
end

function DataService.Start()
	Net.handleInvoke("GetData", {}, function(player)
		return DataService.Get(player)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(releaseProfile)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(settings.AutosaveInterval)
			for player, profile in profiles do
				task.spawn(saveProfile, player, profile, false)
			end
		end
	end)

	game:BindToClose(function()
		for player in profiles do
			task.spawn(releaseProfile, player)
		end
		-- Also waits for releases started by PlayerRemoving during shutdown.
		local deadline = os.clock() + 25
		while (next(profiles) ~= nil or activeSaves > 0) and os.clock() < deadline do
			task.wait()
		end
	end)
end

return DataService
