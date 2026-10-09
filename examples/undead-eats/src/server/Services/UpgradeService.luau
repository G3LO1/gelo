-- Upgrade shop: the team spends run cash on Upgrades.Defs during the Shop phase.
-- Plan: SYS-11 (upgrade shop), UI-06
--
-- Remote BuyUpgrade(id) -> "Bought" | "TooPoor" | "Maxed" | "Closed" (shop only open in the Shop phase)
-- UpgradeService.GetLevel(id) -> level this run
-- Effects: TruckHp -> TruckService.RefreshMaxHp; CookSpeed -> workspace attribute CookSpeed
-- (read by StationService); ExtraSlot -> workspace attribute TurretSlots (for SYS-08 build mode).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Guard = require(ReplicatedStorage.Shared.Guard)
local Net = require(ReplicatedStorage.Shared.Net)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local EconomyService = require(script.Parent.EconomyService)
local GameService = require(script.Parent.GameService)
local TruckService = require(script.Parent.TruckService)

local UpgradeService = {}

function UpgradeService.GetLevel(id: string): number
	return workspace:GetAttribute(Upgrades.attribute(id)) or 0
end

local function applyEffects()
	local cookLevel = UpgradeService.GetLevel("CookSpeed")
	workspace:SetAttribute("CookSpeed", 1 / (1 - Upgrades.Defs.CookSpeed.Reduction) ^ cookLevel)
	workspace:SetAttribute("TurretSlots", Upgrades.BaseTurretSlots + UpgradeService.GetLevel("ExtraSlot"))
	TruckService.RefreshMaxHp()
end

local function resetLevels()
	for _, id in Upgrades.Ids do
		workspace:SetAttribute(Upgrades.attribute(id), 0)
	end
	workspace:SetAttribute("CookSpeed", 1)
	workspace:SetAttribute("TurretSlots", Upgrades.BaseTurretSlots)
end

local function buy(player: Player, id: string): string
	if GameService.GetState() ~= "Shop" then
		return "Closed"
	end
	local level = UpgradeService.GetLevel(id)
	local cost = Upgrades.nextCost(id, level)
	if not cost then
		return "Maxed"
	end
	-- Spend and level-up happen without yielding, so two players can't buy the same level twice.
	if not EconomyService.Spend(cost, player, Enum.AnalyticsEconomyTransactionType.Shop.Name, "Upgrade_" .. id) then
		return "TooPoor"
	end
	workspace:SetAttribute(Upgrades.attribute(id), level + 1)
	applyEffects()
	return "Bought"
end

function UpgradeService.Init()
	resetLevels()
	GameService.OnStateChanged(function(state)
		if state == "Ready" then
			resetLevels()
		end
	end)
end

function UpgradeService.Start()
	Net.handleInvoke("BuyUpgrade", { Guard.oneOf(Upgrades.Ids) }, buy, { rate = 3, burst = 4 })
end

return UpgradeService
