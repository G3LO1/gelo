-- Customers: spawn during the day, queue at free slots, order 1-3 dishes, lose patience,
-- get served at the window, pay per dish and tip for speed.
-- Plan: SYS-05
--
-- World contract (tags):
--   "CustomerSpawn"  one part where customers appear and where they leave to
--   "QueueSlot"      parts with number attribute Index (1 = nearest the window); one customer per slot
--   "ServiceWindow"  part/model; players holding a dish trigger its ProximityPrompt (created if missing)
-- Optional ServerStorage.Customers: models (R15 rigs with Humanoid + HumanoidRootPart) used before the default rig (MOD-06).
--
-- Customers live in workspace.Customers. Replicated attributes on each customer model (UI-03 tickets):
--   Order ("Burger,Fries" = dishes still missing), Total (same list at arrival), Patience (1 -> 0), Waiting (arrived)
--
-- CustomerService.GetWaiting() -> number of customers at the window

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Nights = require(ReplicatedStorage.Shared.Nights)
local Recipes = require(ReplicatedStorage.Shared.Recipes)
local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local GameService = require(script.Parent.GameService)
local PlayerUtil = require(script.Parent.Parent.Lib.PlayerUtil)

local CustomerService = {}

local TICK = 0.25

type Customer = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	slot: BasePart?,
	phase: string, -- "Walking" | "Waiting" | "Leaving"
	order: { string },
	total: { string },
	patience: number, -- seconds left
	patienceTotal: number,
	phaseStart: number,
	lastMove: number,
	paid: number, -- cash earned from dishes already served
}

local customers: { [Model]: Customer } = {}
local slotOwner: { [BasePart]: Customer? } = {}
local reserved = 0 -- spawns in progress (the rig is built asynchronously)
local folder: Folder
local spawnPart: BasePart? = nil
local spawnToken = 0
local rng = Random.new()
local warnedRig = false

local function getSlots(): { BasePart }
	local list = {}
	for _, instance in CollectionService:GetTagged("QueueSlot") do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			table.insert(list, instance)
		end
	end
	table.sort(list, function(a, b)
		return (a:GetAttribute("Index") or 0) < (b:GetAttribute("Index") or 0)
	end)
	return list
end

local function freeSlot(): BasePart?
	for _, slot in getSlots() do
		if slotOwner[slot] == nil then
			return slot
		end
	end
	return nil
end

local function countActive(): number
	local n = reserved
	for _ in customers do
		n += 1
	end
	return n
end

local function publish(customer: Customer)
	local model = customer.model
	model:SetAttribute("Order", table.concat(customer.order, ","))
	model:SetAttribute("Total", table.concat(customer.total, ","))
	model:SetAttribute("Patience", math.floor(math.clamp(customer.patience / customer.patienceTotal, 0, 1) * 100) / 100)
	model:SetAttribute("Waiting", customer.phase == "Waiting")
end

local function buildRig(): Model?
	local templates = ServerStorage:FindFirstChild("Customers")
	if templates then
		local options = templates:GetChildren()
		if #options > 0 then
			local clone = options[rng:NextInteger(1, #options)]:Clone()
			if
				clone:IsA("Model")
				and clone:FindFirstChildOfClass("Humanoid")
				and clone:FindFirstChild("HumanoidRootPart")
			then
				return clone
			end
			clone:Destroy()
		end
	end
	local description = Instance.new("HumanoidDescription")
	for _, property in { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" } do
		description[property] = Color3.fromHSV(rng:NextNumber(), 0.35, 0.9)
	end
	local ok, rig = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R15)
	if ok and rig then
		return rig
	end
	if not warnedRig then
		warnedRig = true
		warn(`[CustomerService] Could not build a customer rig: {rig}`)
	end
	return nil
end

local function makeOrder(night): { string }
	local settings = night.Customers
	local order = {}
	for _ = 1, rng:NextInteger(1, settings.MaxItems) do
		table.insert(order, settings.Dishes[rng:NextInteger(1, #settings.Dishes)])
	end
	return order
end

local function release(customer: Customer, nextPhase: string)
	if customer.slot and slotOwner[customer.slot] == customer then
		slotOwner[customer.slot] = nil
	end
	customer.slot = nil
	customer.phase = nextPhase
	customer.phaseStart = os.clock()
	customer.lastMove = 0
	customer.model:SetAttribute("Waiting", false)
end

local function remove(customer: Customer)
	release(customer, "Leaving")
	customers[customer.model] = nil
	customer.model:Destroy()
end

local function spawnCustomer(token: number)
	local slot = freeSlot()
	local origin = spawnPart
	if not slot or not origin or not origin.Parent then
		return
	end
	local day = math.max(GameService.Run.Day, 1)
	local night = Nights.Days[day]
	reserved += 1
	slotOwner[slot] = {} :: any -- placeholder reserves the slot while the rig loads
	local rig = buildRig()
	reserved -= 1
	if not rig or token ~= spawnToken or GameService.GetState() ~= "Day" then
		slotOwner[slot] = nil
		if rig then
			rig:Destroy()
		end
		return
	end

	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.WalkSpeed = Config.Customers.WalkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	rig.Name = "Customer"
	rig:PivotTo(origin.CFrame + Vector3.new(0, 3, 0))
	rig.Parent = folder
	pcall(root.SetNetworkOwner, root, nil)

	local order = makeOrder(night)
	local patienceTotal = night.Customers.Patience.Base + night.Customers.Patience.PerItem * #order
	local customer: Customer = {
		model = rig,
		humanoid = humanoid,
		root = root,
		slot = slot,
		phase = "Walking",
		order = order,
		total = table.clone(order),
		patience = patienceTotal,
		patienceTotal = patienceTotal,
		phaseStart = os.clock(),
		lastMove = 0,
		paid = 0,
	}
	slotOwner[slot] = customer
	customers[rig] = customer
	publish(customer)
	humanoid.Died:Connect(function()
		if customers[rig] then
			remove(customer)
		end
	end)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function walkTo(customer: Customer, target: Vector3)
	local now = os.clock()
	if now - customer.lastMove >= 1 then
		customer.lastMove = now
		customer.humanoid:MoveTo(target)
	end
end

local function updateCustomer(customer: Customer, now: number)
	if customer.phase == "Walking" then
		local slot = customer.slot
		if not slot then
			return
		end
		if
			flatDistance(customer.root.Position, slot.Position) <= Config.Customers.ArriveDistance
			or now - customer.phaseStart > Config.Customers.WalkTimeout
		then
			if now - customer.phaseStart > Config.Customers.WalkTimeout then
				customer.model:PivotTo(slot.CFrame + Vector3.new(0, 3, 0)) -- stuck: snap to the slot
			end
			customer.phase = "Waiting"
			publish(customer)
		else
			walkTo(customer, slot.Position)
		end
	elseif customer.phase == "Waiting" then
		customer.patience -= TICK
		if customer.patience <= 0 then
			GameService.Run.Lost += 1
			release(customer, "Leaving")
			publish(customer)
		else
			publish(customer)
		end
	elseif customer.phase == "Leaving" then
		local origin = spawnPart
		local arrived = not origin
			or flatDistance(customer.root.Position, origin.Position) <= Config.Customers.ArriveDistance + 2
		if arrived or now - customer.phaseStart > Config.Customers.LeaveTimeout then
			remove(customer)
		elseif origin then
			walkTo(customer, origin.Position)
		end
	end
end

local function clearAll()
	spawnToken += 1
	for _, customer in customers do
		remove(customer)
	end
	table.clear(slotOwner)
end

-- Serves the most urgent waiting customer who still needs `dish`.
local function serve(player: Player, dish: string): boolean
	local best: Customer? = nil
	local bestIndex = 0
	for _, customer in customers do
		if customer.phase == "Waiting" then
			local index = table.find(customer.order, dish)
			if index and (best == nil or customer.patience < best.patience) then
				best, bestIndex = customer, index
			end
		end
	end
	if not best then
		return false
	end

	table.remove(best.order, bestIndex)
	local price = Recipes.Dishes[dish].Price
	EconomyService.Add(price, player, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Dish_" .. dish)
	best.paid += price
	local finished = #best.order == 0
	if finished then
		local fraction = math.clamp(best.patience / best.patienceTotal, 0, 1)
		local multiplier = player:GetAttribute("TipMultiplier")
		multiplier = if type(multiplier) == "number" and multiplier >= 1 and multiplier <= 10 then multiplier else 1
		local tip = math.floor(best.paid * Config.Customers.TipRate * fraction * multiplier)
		if tip > 0 then
			EconomyService.Add(tip, player, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Tip")
		end
		GameService.Run.Served += 1
		release(best, "Leaving")
	end
	publish(best)

	DataService.Update(player, function(data)
		data.Stats.DishesServed += 1
		if finished then
			data.Stats.CustomersServed += 1
		end
	end)
	return true
end

local function setupWindow(window: Instance)
	local prompt = window:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Serve dish"
		prompt.ObjectText = "Window"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Config.Interaction.PromptDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = if window:IsA("Model")
			then (window.PrimaryPart or window:FindFirstChildWhichIsA("BasePart"))
			else window
	end
	prompt.Triggered:Connect(function(player)
		if GameService.GetState() ~= "Day" and GameService.GetState() ~= "Night" then
			return
		end
		if
			not PlayerUtil.isNear(
				player,
				window,
				Config.Interaction.PromptDistance + Config.Interaction.ServerSlack + 10
			)
		then
			return
		end
		local carried = CarryService.Peek(player)
		if not carried or Recipes.Items[carried].Kind ~= "Dish" then
			Net.fireClient(player, "Notify", "Bring a finished dish")
			return
		end
		if serve(player, carried) then
			CarryService.Clear(player)
		else
			Net.fireClient(player, "Notify", "Nobody ordered that")
		end
	end)
end

local function spawnLoop(token: number)
	local day = GameService.Run.Day
	local night = Nights.Days[day]
	if not night then
		return
	end
	local settings = night.Customers
	-- First customer shows up quickly so the loop starts at once.
	task.wait(2)
	while token == spawnToken do
		if countActive() < math.min(settings.MaxActive, #getSlots()) then
			task.spawn(spawnCustomer, token)
		end
		task.wait(settings.SpawnInterval * rng:NextNumber(0.8, 1.2))
	end
end

function CustomerService.GetWaiting(): number
	local n = 0
	for _, customer in customers do
		if customer.phase == "Waiting" then
			n += 1
		end
	end
	return n
end

function CustomerService.Init()
	local existing = workspace:FindFirstChild("Customers")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Customers"
		folder.Parent = workspace
	end

	GameService.OnStateChanged(function(state)
		if state == "Day" then
			spawnToken += 1
			task.spawn(spawnLoop, spawnToken)
		else
			-- Night, Results and Ready: nobody new arrives; waiting customers go home.
			spawnToken += 1
			for _, customer in customers do
				if customer.phase ~= "Leaving" then
					release(customer, "Leaving")
					publish(customer)
				end
			end
			if state == "Ready" then
				clearAll()
			end
		end
	end)
end

function CustomerService.Start()
	local function findSpawn()
		for _, instance in CollectionService:GetTagged("CustomerSpawn") do
			if instance:IsA("BasePart") then
				spawnPart = instance
				return
			end
		end
	end
	findSpawn()
	CollectionService:GetInstanceAddedSignal("CustomerSpawn"):Connect(findSpawn)

	CollectionService:GetInstanceAddedSignal("ServiceWindow"):Connect(setupWindow)
	for _, window in CollectionService:GetTagged("ServiceWindow") do
		setupWindow(window)
	end

	while true do
		task.wait(TICK)
		local now = os.clock()
		for _, customer in customers do
			updateCustomer(customer, now)
		end
	end
end

return CustomerService
