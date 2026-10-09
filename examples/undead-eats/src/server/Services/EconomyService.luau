-- Team cash for the current run (not saved). Replicates as workspace attribute "Cash".
-- Plan: SYS-05 (payment and tips); SYS-11 will extend it with rewards and the upgrade shop.
--
-- EconomyService.Get()                              -> cash
-- EconomyService.Add(amount, player?, txType, sku)  -> boolean
-- EconomyService.Spend(amount, player?, txType, sku)-> boolean (false and no change if too poor)
-- `player` is only used to attribute the analytics event.

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GameService = require(script.Parent.GameService)

local EconomyService = {}

local CURRENCY = "Cash"

local function isAmount(amount: any): boolean
	return type(amount) == "number"
		and amount == amount
		and amount > 0
		and amount < 1e9
		and math.floor(amount) == amount
end

local function logEvent(
	player: Player?,
	flow: Enum.AnalyticsEconomyFlowType,
	amount: number,
	txType: string,
	sku: string
)
	if not player or player.Parent == nil then
		return
	end
	local ok, err = pcall(function()
		-- Order per create.roblox.com: currencyType, amount, endingBalance.
		AnalyticsService:LogEconomyEvent(player, flow, CURRENCY, amount, EconomyService.Get(), txType, sku)
	end)
	if not ok then
		warn(`[EconomyService] LogEconomyEvent failed: {err}`)
	end
end

function EconomyService.Get(): number
	return workspace:GetAttribute(CURRENCY) or 0
end

function EconomyService.Add(amount: number, player: Player?, txType: string?, sku: string?): boolean
	if not isAmount(amount) then
		return false
	end
	workspace:SetAttribute(CURRENCY, EconomyService.Get() + amount)
	GameService.Run.Earned += amount
	logEvent(
		player,
		Enum.AnalyticsEconomyFlowType.Source,
		amount,
		txType or Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
		sku or "Unknown"
	)
	return true
end

function EconomyService.Spend(amount: number, player: Player?, txType: string?, sku: string?): boolean
	if not isAmount(amount) or EconomyService.Get() < amount then
		return false
	end
	workspace:SetAttribute(CURRENCY, EconomyService.Get() - amount)
	logEvent(
		player,
		Enum.AnalyticsEconomyFlowType.Sink,
		amount,
		txType or Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
		sku or "Unknown"
	)
	return true
end

function EconomyService.Init()
	workspace:SetAttribute(CURRENCY, Config.Run.StartCash)
	GameService.OnStateChanged(function(state)
		if state == "Ready" then
			workspace:SetAttribute(CURRENCY, Config.Run.StartCash)
		end
	end)
end

return EconomyService
