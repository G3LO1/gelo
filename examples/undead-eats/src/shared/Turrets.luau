-- Turret and trap tuning. Data only; the logic arrives with SYS-08..SYS-10.
-- Plan: SYS-01 (Turrets table)
-- Ammo is an ingredient or dish id from Recipes.Items; one item loads AmmoPerItem shots.

local Turrets = {}

Turrets.Turrets = {
	KetchupGatling = {
		Name = "Ketchup Gatling",
		Cost = 60,
		Range = 40,
		Damage = 6,
		FireRate = 6, -- shots per second
		Ammo = "Potato",
		AmmoPerItem = 30,
		AmmoCapacity = 90,
	},
	PieCannon = { -- first on the cut list
		Name = "Pie Cannon",
		Cost = 110,
		Range = 55,
		Damage = 30,
		Radius = 8, -- area damage
		FireRate = 0.5,
		Ammo = "Dough",
		AmmoPerItem = 3,
		AmmoCapacity = 9,
	},
	HotSauceSprayer = {
		Name = "Hot Sauce Sprayer",
		Cost = 80,
		Range = 18,
		Damage = 3, -- per tick
		DotSeconds = 4,
		FireRate = 4,
		Ammo = "Sausage",
		AmmoPerItem = 20,
		AmmoCapacity = 60,
	},
}

Turrets.Traps = {
	GreaseSlick = {
		Name = "Grease Slick",
		Cost = 25,
		Radius = 7,
		SlowFactor = 0.4, -- walk speed multiplier while inside
		Lifetime = 40,
	},
	ChiliMine = { -- cut-list candidate
		Name = "Chili Mine",
		Cost = 40,
		Radius = 10,
		Damage = 120,
		Lifetime = 60, -- single use
	},
}

Turrets.TurretIds = {} :: { string }
Turrets.TrapIds = {} :: { string }
for id in Turrets.Turrets do
	table.insert(Turrets.TurretIds, id)
end
for id in Turrets.Traps do
	table.insert(Turrets.TrapIds, id)
end
table.sort(Turrets.TurretIds)
table.sort(Turrets.TrapIds)

return Turrets
