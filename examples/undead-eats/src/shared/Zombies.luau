-- Zombie types. Data only; the spawner and AI arrive with SYS-06.
-- Plan: SYS-01 (Zombies table)

local Zombies = {}

Zombies.Types = {
	Walker = { Name = "Walker", Health = 60, WalkSpeed = 8, Damage = 5, AttackInterval = 1.5, Reward = 5 },
	Runner = { Name = "Runner", Health = 35, WalkSpeed = 15, Damage = 4, AttackInterval = 1, Reward = 7 },
	Tank = { Name = "Tank", Health = 300, WalkSpeed = 5, Damage = 20, AttackInterval = 2.5, Reward = 25 },
}

Zombies.TypeIds = {} :: { string }
for id in Zombies.Types do
	table.insert(Zombies.TypeIds, id)
end
table.sort(Zombies.TypeIds)

return Zombies
