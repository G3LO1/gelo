-- Bringforth Studio plugin: inserts the models that bringforth.py uploaded, straight into the open place.
--
-- It reads the local feed of `bringforth.py serve` (http://127.0.0.1:34873/assets, nothing leaves the
-- machine; started with another --port, change FEED_URL below) and has two toolbar buttons:
--   Import latest   insert the newest uploaded model in front of the camera
--   Auto import     keep watching the feed and insert every new upload (or new FBX version) as it lands
-- Inserts are undoable (one ChangeHistory step each) and land in Workspace.Map.Props when that folder
-- exists (the roblox-map-builder layout), otherwise in Workspace. Studio asks once to allow HTTP
-- requests to 127.0.0.1: allow it. Install: `bringforth.py install-plugin`, then restart Studio.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local Selection = game:GetService("Selection")

local FEED_URL = "http://127.0.0.1:34873"
local POLL_SECONDS = 2
local SEEN_SETTING = "BringforthSeen"

type Entry = {
	file: string,
	assetId: number,
	assetType: string,
	name: string?,
	version: string?,
	uploadedAt: string?,
	moderation: string?,
}

local toolbar = plugin:CreateToolbar("Bringforth")
local importButton = toolbar:CreateButton("Import latest", "Insert the newest model uploaded with bringforth.py", "")
local autoButton = toolbar:CreateButton("Auto import", "Insert every new model upload as it lands", "")
importButton.ClickableWhenViewportHidden = true
autoButton.ClickableWhenViewportHidden = true

-- "assetId@version" for everything already inserted or deliberately skipped.
local seen: { [string]: boolean } = {}
do
	local saved = plugin:GetSetting(SEEN_SETTING)
	if type(saved) == "table" then
		for _, key in saved do
			if type(key) == "string" then
				seen[key] = true
			end
		end
	end
end

local function saveSeen()
	local list = {}
	for key in seen do
		table.insert(list, key)
	end
	table.sort(list)
	while #list > 500 do
		table.remove(list, 1)
	end
	plugin:SetSetting(SEEN_SETTING, list)
end

local function seenKey(entry: Entry): string
	return `{entry.assetId}@{entry.version or "1"}`
end

local function fetch(): { Entry }?
	local ok, body = pcall(HttpService.GetAsync, HttpService, FEED_URL .. "/assets", true)
	if not ok then
		warn(`[Bringforth] feed not reachable at {FEED_URL} (run: bringforth.py serve): {body}`)
		return nil
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, body)
	if not decoded or type(data) ~= "table" or type(data.assets) ~= "table" then
		warn("[Bringforth] the feed did not return { assets = [...] }")
		return nil
	end
	local models = {}
	for _, entry in data.assets do
		if type(entry) == "table" and entry.assetType == "Model" and tonumber(entry.assetId) then
			entry.assetId = tonumber(entry.assetId)
			table.insert(models, entry)
		end
	end
	return models
end

local function target(): Instance
	local map = workspace:FindFirstChild("Map")
	local props = map and map:FindFirstChild("Props")
	return props or workspace
end

local function placeInFront(instance: Instance)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local spot = camera.CFrame.Position + camera.CFrame.LookVector * 24
	if instance:IsA("PVInstance") then
		local pivot = instance:GetPivot()
		instance:PivotTo(CFrame.new(spot) * pivot.Rotation)
	end
end

local function insert(entry: Entry): boolean
	if entry.moderation == "rejected" then
		warn(`[Bringforth] {entry.file}: moderation rejected asset {entry.assetId}, not inserting`)
		return false
	end
	local recording = ChangeHistoryService:TryBeginRecording("Bringforth import", `Insert {entry.name or entry.file}`)
	local ok, container = pcall(InsertService.LoadAsset, InsertService, entry.assetId)
	if not ok or not container then
		if recording then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
		end
		warn(
			`[Bringforth] could not load asset {entry.assetId} ({entry.file}): {container}. Still in moderation, `
				.. "or owned by another account/group than the one signed in to Studio?"
		)
		return false
	end
	local parent = target()
	local inserted = {}
	for _, child in container:GetChildren() do
		child.Parent = parent
		placeInFront(child)
		child:SetAttribute("BringforthAssetId", entry.assetId)
		child:SetAttribute("BringforthFile", entry.file)
		table.insert(inserted, child)
	end
	container:Destroy()
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	Selection:Set(inserted)
	print(`[Bringforth] inserted {entry.name or entry.file} (asset {entry.assetId}) into {parent:GetFullName()}`)
	return true
end

local function importLatest()
	local models = fetch()
	if not models then
		return
	end
	local latest = models[#models]
	if not latest then
		print("[Bringforth] no models uploaded yet: bringforth.py upload model.glb")
		return
	end
	if insert(latest) then
		seen[seenKey(latest)] = true
		saveSeen()
	end
end

local autoOn = false

local function poll()
	while autoOn do
		local models = fetch()
		if models then
			local changed = false
			for _, entry in models do
				local key = seenKey(entry)
				if not seen[key] then
					seen[key] = true
					changed = true
					insert(entry)
				end
			end
			if changed then
				saveSeen()
			end
		end
		task.wait(POLL_SECONDS)
	end
end

local function setAuto(on: boolean)
	autoOn = on
	autoButton:SetActive(on)
	if not on then
		return
	end
	-- Start from now: what was uploaded before turning it on is not inserted again.
	local models = fetch()
	if models then
		for _, entry in models do
			seen[seenKey(entry)] = true
		end
		saveSeen()
	end
	print(`[Bringforth] auto import on, watching {FEED_URL}`)
	task.spawn(poll)
end

importButton.Click:Connect(importLatest)
autoButton.Click:Connect(function()
	setAuto(not autoOn)
end)

plugin.Unloading:Connect(function()
	autoOn = false
end)
