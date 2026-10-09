-- Truck health for the current run. Replicates as workspace attributes TruckHp / TruckMaxHp,
-- so the HUD needs no remote.
-- Plan: SYS-07 (partial: health model and loss). TODO(SYS-07): hold-to-repair interaction once the
-- truck model exists; SYS-06 zombies call TruckService.Damage.
--
-- TruckService.Get()            -> hp, maxHp
-- TruckService.Damage(amount)   -> remaining hp; reaching 0 ends the run (GameService.Lose("TruckDestroyed"))
-- TruckService.Repair(amount)   -> new hp (never above max)
-- TruckService.RefreshMaxHp()   -> re-reads the TruckHp upgrade; extra max HP is added as health too

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local GameService = require(script.Parent.GameService)

local TruckService = {}

local function isAmount(amount: any): boolean
	return type(amount) == "number" and amount == amount and amount > 0 and amount < 1e9
end

local function maxHpFromUpgrades(): number
	local level = workspace:GetAttribute(Upgrades.attribute("TruckHp")) or 0
	return Config.Truck.BaseHp + level * Upgrades.Defs.TruckHp.PerLevel
end

local function set(hp: number, maxHp: number)
	workspace:SetAttribute("TruckMaxHp", maxHp)
	workspace:SetAttribute("TruckHp", math.clamp(hp, 0, maxHp))
end

function TruckService.Get(): (number, number)
	return workspace:GetAttribute("TruckHp") or 0, workspace:GetAttribute("TruckMaxHp") or Config.Truck.BaseHp
end

function TruckService.Damage(amount: number): number
	local hp, maxHp = TruckService.Get()
	local state = GameService.GetState()
	if not isAmount(amount) or hp <= 0 or (state ~= "Day" and state ~= "Night") then
		return hp
	end
	hp = math.max(0, hp - amount)
	set(hp, maxHp)
	if hp == 0 then
		GameService.Lose("TruckDestroyed")
	end
	return hp
end

function TruckService.Repair(amount: number): number
	local hp, maxHp = TruckService.Get()
	if not isAmount(amount) or hp <= 0 then
		return hp
	end
	set(hp + amount, maxHp)
	return (TruckService.Get())
end

function TruckService.RefreshMaxHp()
	local hp, oldMax = TruckService.Get()
	local newMax = maxHpFromUpgrades()
	set(hp + math.max(0, newMax - oldMax), newMax)
end

function TruckService.Init()
	set(Config.Truck.BaseHp, Config.Truck.BaseHp)
	GameService.OnStateChanged(function(state)
		if state == "Ready" then
			-- New run: upgrades are reset too, so the base values apply.
			set(Config.Truck.BaseHp, Config.Truck.BaseHp)
		end
	end)
end

return TruckService
