-- TEMPORARY prototype world (M1): builds a floor, ingredient crates, three stations, the service
-- window, queue slots and the customer spawn from plain parts, only when the map has no tagged
-- objects. Delete this file (or set Config.Greybox = false) once MAP-01 provides the real ones.
-- The tag/attribute contract is described in README.md.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Recipes = require(ReplicatedStorage.Shared.Recipes)

local GreyboxService = {}

local function addPart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.Parent = parent
	return part
end

local function label(part: Part, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 30)
	gui.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 2, 0)
	gui.AlwaysOnTop = true
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.TextStrokeTransparency = 0.4
	textLabel.Text = text
	textLabel.Parent = gui
	gui.Parent = part
end

function GreyboxService.Init()
	if not Config.Greybox then
		return
	end
	for _, tag in { "Station", "IngredientCrate", "ServiceWindow", "QueueSlot", "CustomerSpawn" } do
		if #CollectionService:GetTagged(tag) > 0 then
			return
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "Greybox"

	addPart(folder, "Floor", Vector3.new(120, 1, 120), Vector3.new(0, -0.5, 0), Color3.fromRGB(90, 95, 100))

	local window =
		addPart(folder, "ServiceWindow", Vector3.new(10, 6, 1), Vector3.new(0, 3, -10), Color3.fromRGB(220, 90, 70))
	CollectionService:AddTag(window, "ServiceWindow")
	label(window, "Window")

	for index = 1, 4 do
		local slot = addPart(
			folder,
			"QueueSlot" .. index,
			Vector3.new(4, 0.2, 4),
			Vector3.new((index - 2.5) * 5, 0.1, -18),
			Color3.fromRGB(240, 220, 120)
		)
		slot.CanCollide = false
		slot:SetAttribute("Index", index)
		CollectionService:AddTag(slot, "QueueSlot")
	end

	local spawn = addPart(
		folder,
		"CustomerSpawn",
		Vector3.new(4, 0.2, 4),
		Vector3.new(40, 0.1, -30),
		Color3.fromRGB(120, 120, 120)
	)
	spawn.CanCollide = false
	CollectionService:AddTag(spawn, "CustomerSpawn")

	for index, stationType in Recipes.StationIds do
		local station = addPart(
			folder,
			stationType,
			Vector3.new(6, 4, 4),
			Vector3.new((index - 2) * 12, 2, 8),
			Color3.fromRGB(70, 70, 80)
		)
		station:SetAttribute("StationType", stationType)
		CollectionService:AddTag(station, "Station")
		label(station, stationType)
	end

	for index, ingredient in Recipes.IngredientIds do
		local crate = addPart(
			folder,
			ingredient .. "Crate",
			Vector3.new(4, 3, 4),
			Vector3.new((index - 3.5) * 8, 1.5, 28),
			Recipes.Items[ingredient].Color
		)
		crate:SetAttribute("Ingredient", ingredient)
		CollectionService:AddTag(crate, "IngredientCrate")
		label(crate, ingredient)
	end

	if not workspace:FindFirstChildWhichIsA("SpawnLocation") then
		local spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Anchored = true
		spawnLocation.Size = Vector3.new(8, 1, 8)
		spawnLocation.Position = Vector3.new(0, 0.5, 0)
		spawnLocation.Neutral = true
		spawnLocation.Parent = folder
	end

	folder.Parent = workspace
end

return GreyboxService
