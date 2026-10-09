-- One carried item per player, welded to the right hand. The server owns the slot; the
-- client can only ask to drop (DropItem). Ingredient crates give items.
-- Plan: SYS-03
--
-- CarryService.Give(player, itemId) -> boolean (false if hands full, dead or unknown item)
-- CarryService.Peek(player)         -> itemId or nil
-- CarryService.Take(player)         -> itemId or nil, empties the slot
-- CarryService.Clear(player)        -> empties the slot
-- Player attribute "Carrying" (item id or nil) replicates for UI-04 and the hold-tray animation (ANI-02).
--
-- World contract: parts/models tagged "IngredientCrate" with attribute Ingredient = <Recipes ingredient id>.
-- A ProximityPrompt is created if the crate has none. Optional ServerStorage.ItemModels.<itemId> (Model with
-- PrimaryPart, or a BasePart) replaces the placeholder cube.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Recipes = require(ReplicatedStorage.Shared.Recipes)
local GameService = require(script.Parent.GameService)
local PlayerUtil = require(script.Parent.Parent.Lib.PlayerUtil)

local CarryService = {}

local ATTRIBUTE = "Carrying"

type Slot = { id: string, visual: Instance, died: RBXScriptConnection? }
local slots: { [Player]: Slot } = {}

local function buildVisual(itemId: string): (Instance, BasePart)
	local models = ServerStorage:FindFirstChild("ItemModels")
	local template = models and models:FindFirstChild(itemId)
	if template then
		local clone = template:Clone()
		local root = if clone:IsA("Model") then clone.PrimaryPart else clone
		if root and root:IsA("BasePart") then
			return clone, root
		end
		clone:Destroy()
	end
	local part = Instance.new("Part")
	part.Name = "Carried_" .. itemId
	part.Size = Config.Carry.ItemSize
	part.Color = Recipes.Items[itemId].Color
	part.Material = Enum.Material.SmoothPlastic
	return part, part
end

local function releaseVisual(slot: Slot)
	if slot.died then
		slot.died:Disconnect()
	end
	slot.visual:Destroy()
end

function CarryService.Peek(player: Player): string?
	local slot = slots[player]
	return if slot then slot.id else nil
end

function CarryService.Clear(player: Player)
	local slot = slots[player]
	if not slot then
		return
	end
	slots[player] = nil
	releaseVisual(slot)
	player:SetAttribute(ATTRIBUTE, nil)
end

function CarryService.Take(player: Player): string?
	local id = CarryService.Peek(player)
	if id then
		CarryService.Clear(player)
	end
	return id
end

function CarryService.Give(player: Player, itemId: string): boolean
	if slots[player] or not Recipes.Items[itemId] or not PlayerUtil.getRoot(player) then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if not (character and humanoid and hand and hand:IsA("BasePart")) then
		return false
	end

	local visual, root = buildVisual(itemId)
	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	if visual:IsA("BasePart") then
		visual.CanCollide = false
		visual.CanQuery = false
		visual.CanTouch = false
		visual.Massless = true
	end
	root.CFrame = hand.CFrame * Config.Carry.GripOffset

	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = hand
	weld.Part1 = root
	weld.C0 = Config.Carry.GripOffset
	weld.Parent = root
	visual.Parent = character

	local slot: Slot = { id = itemId, visual = visual, died = nil }
	slot.died = humanoid.Died:Connect(function()
		CarryService.Clear(player)
	end)
	slots[player] = slot
	player:SetAttribute(ATTRIBUTE, itemId)
	return true
end

local function setupCrate(crate: Instance)
	local ingredient = crate:GetAttribute("Ingredient")
	if
		type(ingredient) ~= "string"
		or not Recipes.Items[ingredient]
		or Recipes.Items[ingredient].Kind ~= "Ingredient"
	then
		warn(`[CarryService] Crate {crate:GetFullName()} has no valid Ingredient attribute`)
		return
	end
	local prompt = crate:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Take " .. Recipes.Items[ingredient].Name
		prompt.ObjectText = "Crate"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Config.Interaction.PromptDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = if crate:IsA("Model")
			then (crate.PrimaryPart or crate:FindFirstChildWhichIsA("BasePart"))
			else crate
	end
	prompt.Triggered:Connect(function(player)
		local state = GameService.GetState()
		if state ~= "Day" and state ~= "Night" then
			return
		end
		if
			not PlayerUtil.isNear(
				player,
				crate,
				Config.Interaction.PromptDistance + Config.Interaction.ServerSlack + 10
			)
		then
			return
		end
		if CarryService.Peek(player) then
			Net.fireClient(player, "Notify", "Your hands are full (G to drop)")
			return
		end
		CarryService.Give(player, ingredient)
	end)
end

function CarryService.Init()
	GameService.OnStateChanged(function(state)
		if state == "Ready" then
			for player in slots do
				CarryService.Clear(player)
			end
		end
	end)
end

function CarryService.Start()
	Net.handle("DropItem", {}, function(player)
		CarryService.Clear(player)
	end, { rate = 3 })

	Players.PlayerRemoving:Connect(CarryService.Clear)
	local function watchCharacter(player: Player)
		player.CharacterRemoving:Connect(function()
			CarryService.Clear(player)
		end)
	end
	Players.PlayerAdded:Connect(watchCharacter)
	for _, player in Players:GetPlayers() do
		watchCharacter(player)
	end

	CollectionService:GetInstanceAddedSignal("IngredientCrate"):Connect(setupCrate)
	for _, crate in CollectionService:GetTagged("IngredientCrate") do
		setupCrate(crate)
	end
end

return CarryService
