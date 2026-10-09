-- Per-day tuning: how long each phase lasts, how customers behave by day and which
-- zombie waves come at night. One entry per day of a run (Config.Run.Days).
-- Plan: SYS-01 (Nights table), SYS-02 (durations), SYS-05 (Customers), SYS-06 (Waves)
--
-- Customers: SpawnInterval (s between arrivals), MaxActive (<= number of queue slots),
--            Patience = Base + PerItem * items in the order, MaxItems (dishes per order),
--            Dishes (dish ids that may be ordered that day)
-- Waves:     { At = seconds after night start, Zombie = Zombies.Types id, Count, Gate = 1..3 }

local Nights = {}

local function day(dayDuration: number, nightDuration: number, customers: any, waves: any)
	return { DayDuration = dayDuration, NightDuration = nightDuration, Customers = customers, Waves = waves }
end

Nights.Days = {
	day(150, 90, {
		SpawnInterval = 14,
		MaxActive = 3,
		Patience = { Base = 35, PerItem = 15 },
		MaxItems = 1,
		Dishes = { "Burger", "Fries" },
	}, {
		{ At = 5, Zombie = "Walker", Count = 3, Gate = 1 },
		{ At = 40, Zombie = "Walker", Count = 4, Gate = 2 },
	}),
	day(150, 100, {
		SpawnInterval = 12,
		MaxActive = 4,
		Patience = { Base = 32, PerItem = 14 },
		MaxItems = 2,
		Dishes = { "Burger", "Fries", "HotDog" },
	}, {
		{ At = 5, Zombie = "Walker", Count = 4, Gate = 1 },
		{ At = 30, Zombie = "Runner", Count = 2, Gate = 3 },
		{ At = 55, Zombie = "Walker", Count = 5, Gate = 2 },
	}),
	day(150, 105, {
		SpawnInterval = 11,
		MaxActive = 4,
		Patience = { Base = 30, PerItem = 13 },
		MaxItems = 2,
		Dishes = { "Burger", "Fries", "HotDog", "Pizza" },
	}, {
		{ At = 5, Zombie = "Walker", Count = 5, Gate = 1 },
		{ At = 30, Zombie = "Runner", Count = 3, Gate = 3 },
		{ At = 60, Zombie = "Walker", Count = 6, Gate = 2 },
	}),
	day(150, 110, {
		SpawnInterval = 10,
		MaxActive = 4,
		Patience = { Base = 28, PerItem = 12 },
		MaxItems = 3,
		Dishes = { "Burger", "Fries", "HotDog", "Pizza" },
	}, {
		{ At = 5, Zombie = "Walker", Count = 6, Gate = 1 },
		{ At = 25, Zombie = "Tank", Count = 1, Gate = 2 },
		{ At = 55, Zombie = "Runner", Count = 4, Gate = 3 },
	}),
	day(150, 120, {
		SpawnInterval = 9,
		MaxActive = 4,
		Patience = { Base = 26, PerItem = 12 },
		MaxItems = 3,
		Dishes = { "Burger", "Fries", "HotDog", "Pizza" },
	}, {
		{ At = 5, Zombie = "Walker", Count = 7, Gate = 1 },
		{ At = 25, Zombie = "Tank", Count = 2, Gate = 2 },
		{ At = 50, Zombie = "Runner", Count = 5, Gate = 3 },
		{ At = 80, Zombie = "Walker", Count = 8, Gate = 2 },
	}),
}

return Nights
