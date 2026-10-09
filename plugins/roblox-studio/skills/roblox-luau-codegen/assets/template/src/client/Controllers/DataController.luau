-- Read-only copy of this player's data for UI. The server is the only source of truth;
-- changing this table does nothing except confuse your UI.
--
-- DataController.Get()              -> latest data or nil before the first sync
-- DataController.OnChanged(callback) -> callback(data) now (if loaded) and after every change

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local DataController = {}

local current: any = nil
local callbacks: { (any) -> () } = {}

local function set(data: any)
	if data == nil then
		return
	end
	current = data
	for _, callback in callbacks do
		task.spawn(callback, data)
	end
end

function DataController.Get(): any
	return current
end

function DataController.OnChanged(callback: (any) -> ())
	table.insert(callbacks, callback)
	if current ~= nil then
		task.spawn(callback, current)
	end
end

function DataController.Init() end

function DataController.Start()
	Net.on("DataSync", set)
	-- Covers the sync that may have fired before this controller connected.
	set(Net.invoke("GetData"))
end

return DataController
