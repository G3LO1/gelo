-- Cooking stations: Grill, Fryer, Oven. Bring ingredients one at a time; when the inputs
-- match a recipe the station cooks, then the dish waits to be collected and burns if left.
-- Plan: SYS-04
--
-- World contract: parts/models tagged "Station" with attribute StationType = <Recipes.Stations id>.
-- A ProximityPrompt is created if missing. Replicated attributes on the station (for progress bars, UI/VFX):
--   State ("Idle" | "Loading" | "Cooking" | "Done" | "Burnt"), Progress (0-1 cooking), BurnProgress (0-1),
--   Dish (dish id while Cooking/Done), Inputs ("Bun,Patty")
-- workspace attribute CookSpeed (default 1) scales cooking speed (upgrade shop, SYS-11).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Recipes = require(ReplicatedStorage.Shared.Recipes)
local CarryService = require(script.Parent.CarryService)
local GameService = require(script.Parent.GameService)
local PlayerUtil = require(script.Parent.Parent.Lib.PlayerUtil)

local StationService = {}

local TICK = 0.1

type Station = {
	instance: Instance,
	stationType: string,
	prompt: ProximityPrompt,
	state: string,
	inputs: { string },
	dish: string?,
	elapsed: number,
	doneAt: number,
}

local stations: { [Instance]: Station } = {}

local function publish(station: Station)
	local instance = station.instance
	instance:SetAttribute("State", station.state)
	instance:SetAttribute("Inputs", table.concat(station.inputs, ","))
	instance:SetAttribute("Dish", station.dish)
	local progress, burn = 0, 0
	if station.dish then
		local recipe = Recipes.Dishes[station.dish]
		if station.state == "Cooking" then
			progress = station.elapsed / recipe.CookTime
		elseif station.state == "Done" then
			progress = 1
			burn = (os.clock() - station.doneAt) / recipe.BurnTime
		elseif station.state == "Burnt" then
			progress, burn = 1, 1
		end
	end
	instance:SetAttribute("Progress", math.floor(math.clamp(progress, 0, 1) * 100) / 100)
	instance:SetAttribute("BurnProgress", math.floor(math.clamp(burn, 0, 1) * 100) / 100)

	local stationName = Recipes.Stations[station.stationType].Name
	station.prompt.ObjectText = stationName
	if station.state == "Done" then
		station.prompt.ActionText = "Take " .. Recipes.Dishes[station.dish :: string].Name
	elseif station.state == "Burnt" then
		station.prompt.ActionText = "Throw away burnt food"
	elseif station.state == "Cooking" then
		station.prompt.ActionText = "Cooking..."
	else
		station.prompt.ActionText = "Add ingredient"
	end
end

local function reset(station: Station)
	station.state = "Idle"
	station.inputs = {}
	station.dish = nil
	station.elapsed = 0
	station.doneAt = 0
	publish(station)
end

local function deposit(player: Player, station: Station)
	local carried = CarryService.Peek(player)
	local item = carried and Recipes.Items[carried]
	if not carried or not item or item.Kind ~= "Ingredient" then
		Net.fireClient(player, "Notify", "Bring an ingredient")
		return
	end
	if not Recipes.canAccept(station.stationType, station.inputs, carried) then
		Net.fireClient(player, "Notify", "That doesn't go in here")
		return
	end
	CarryService.Clear(player)
	table.insert(station.inputs, carried)
	local dish = Recipes.findDish(station.stationType, station.inputs)
	if dish then
		station.state = "Cooking"
		station.dish = dish
		station.elapsed = 0
	else
		station.state = "Loading"
	end
	publish(station)
end

local function onTriggered(station: Station, player: Player)
	local state = GameService.GetState()
	if state ~= "Day" and state ~= "Night" then
		return
	end
	if
		not PlayerUtil.isNear(
			player,
			station.instance,
			Config.Interaction.PromptDistance + Config.Interaction.ServerSlack + 10
		)
	then
		return
	end
	if station.state == "Idle" or station.state == "Loading" then
		deposit(player, station)
	elseif station.state == "Done" then
		if CarryService.Peek(player) then
			Net.fireClient(player, "Notify", "Your hands are full (G to drop)")
			return
		end
		if CarryService.Give(player, station.dish :: string) then
			reset(station)
		end
	elseif station.state == "Burnt" then
		reset(station)
	end
end

local function setupStation(instance: Instance)
	local stationType = instance:GetAttribute("StationType")
	if stations[instance] or type(stationType) ~= "string" or not Recipes.Stations[stationType] then
		if not stations[instance] then
			warn(`[StationService] {instance:GetFullName()} has no valid StationType attribute`)
		end
		return
	end
	local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Config.Interaction.PromptDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = if instance:IsA("Model")
			then (instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart"))
			else instance
	end
	local station: Station = {
		instance = instance,
		stationType = stationType,
		prompt = prompt,
		state = "Idle",
		inputs = {},
		dish = nil,
		elapsed = 0,
		doneAt = 0,
	}
	stations[instance] = station
	prompt.Triggered:Connect(function(player)
		onTriggered(station, player)
	end)
	instance.Destroying:Connect(function()
		stations[instance] = nil
	end)
	reset(station)
end

local function step(dt: number)
	local speed = math.clamp(workspace:GetAttribute("CookSpeed") or 1, 0.1, 10)
	local now = os.clock()
	for _, station in stations do
		if station.state == "Cooking" then
			station.elapsed += dt * speed
			if station.elapsed >= Recipes.Dishes[station.dish :: string].CookTime then
				station.state = "Done"
				station.doneAt = now
			end
			publish(station)
		elseif station.state == "Done" then
			if now - station.doneAt >= Recipes.Dishes[station.dish :: string].BurnTime then
				station.state = "Burnt"
			end
			publish(station)
		end
	end
end

function StationService.Init()
	GameService.OnStateChanged(function(state)
		if state == "Ready" then
			for _, station in stations do
				reset(station)
			end
		end
	end)
end

function StationService.Start()
	CollectionService:GetInstanceAddedSignal("Station"):Connect(setupStation)
	for _, instance in CollectionService:GetTagged("Station") do
		setupStation(instance)
	end
	local last = os.clock()
	while true do
		task.wait(TICK)
		local now = os.clock()
		step(now - last)
		last = now
	end
end

return StationService
