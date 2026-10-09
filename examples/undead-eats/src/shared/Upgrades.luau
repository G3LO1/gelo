-- Run upgrades sold in the Shop phase (between a night and the next day). Shared so the
-- shop UI shows the same costs the server charges; the server is the only one that charges.
-- Plan: SYS-11 (upgrade shop), UI-06
--
-- Levels replicate as workspace attributes "Upgrade_<Id>" (reset every run).

local Upgrades = {}

export type Def = {
	MaxLevel: number,
	Costs: { number }, -- Costs[n] = price of level n
}

Upgrades.Defs = {
	-- +PerLevel max HP (and heals by the same amount when bought).
	TruckHp = { MaxLevel = 5, Costs = { 150, 250, 400, 600, 850 }, PerLevel = 25 },
	-- Each level cuts cooking time by Reduction (multiplicative): time x (1 - Reduction)^level.
	CookSpeed = { MaxLevel = 5, Costs = { 200, 325, 500, 725, 1000 }, Reduction = 0.12 },
	-- +1 turret slot per level on top of BaseTurretSlots (read by the build mode, SYS-08).
	ExtraSlot = { MaxLevel = 3, Costs = { 300, 550, 900 } },
}

Upgrades.Ids = {} :: { string }
for id in Upgrades.Defs do
	table.insert(Upgrades.Ids, id)
end
table.sort(Upgrades.Ids)

Upgrades.BaseTurretSlots = 3

function Upgrades.attribute(id: string): string
	return "Upgrade_" .. id
end

-- Price of the next level, or nil when maxed.
function Upgrades.nextCost(id: string, level: number): number?
	local def = Upgrades.Defs[id]
	if not def or level >= def.MaxLevel then
		return nil
	end
	return def.Costs[level + 1]
end

return Upgrades
