-- Game-wide settings shared by server and client. Keep secrets and prices that the
-- server enforces here too: the client can read them, but only the server trusts them.
-- Plan: SYS-01, DATA-01

local Config = {}

Config.Data = {
	-- Changing StoreName starts everyone from scratch. Bump Version + add a migration instead.
	StoreName = "PlayerData_v1",
	KeyPrefix = "Player_",
	AutosaveInterval = 120,
	-- A lock older than this is treated as left behind by a crashed server. Keep it well above AutosaveInterval.
	LockExpireSeconds = 600,
	LoadRetries = 5,
	-- In Studio without "Enable Studio Access to API Services", fall back to an in-memory store.
	UseMockInStudio = true,
	Version = 1,
	-- Migrations[n] upgrades data saved with Version n - 1 to Version n, e.g.
	-- [2] = function(data) data.Stats.Foo = data.Stats.Foo or 0 end,
	Migrations = {} :: { [number]: (data: any) -> () },
}

-- Every new field added here is filled in for existing players on load.
-- Run state (cash, day, truck HP) is NOT saved: a run lives and dies with the server.
Config.DefaultData = {
	Version = 1,
	Stats = {
		RunsWon = 0,
		RunsLost = 0,
		BestDay = 0,
		CustomersServed = 0,
		DishesServed = 0,
	},
	Settings = {
		Music = 1,
		SFX = 1,
		ReduceFlashes = false,
	},
	TutorialStep = 0,
	PurchaseHistory = {},
}

Config.Run = {
	Days = 5,
	MinPlayers = 1,
	ReadySeconds = 10, -- countdown before a run starts, once MinPlayers is reached
	ResultsSeconds = 12,
	ShopSeconds = 25, -- upgrade shop between a night and the next day (SYS-11)
	StartCash = 0,
}

Config.Truck = {
	BaseHp = 100, -- per run; the TruckHp upgrade adds Upgrades.Defs.TruckHp.PerLevel each level
}

Config.Interaction = {
	PromptDistance = 10, -- studs, ProximityPrompt.MaxActivationDistance
	ServerSlack = 6, -- extra studs the server tolerates for latency
}

Config.Carry = {
	-- Offset of the carried item from the right hand (hand-local space).
	GripOffset = CFrame.new(0, -0.4, -0.7),
	ItemSize = Vector3.new(1.2, 1.2, 1.2),
}

Config.Customers = {
	WalkSpeed = 10,
	TipRate = 0.5, -- tip = dish price * TipRate * remaining patience fraction
	ArriveDistance = 3,
	WalkTimeout = 30, -- seconds before a stuck customer is teleported to its slot
	LeaveTimeout = 12,
}

-- Temporary world for the M1 prototype: builds crates, stations, window and queue slots
-- when the map has none. Set to false once MAP-01 provides tagged objects (see README.md).
Config.Greybox = true

-- Create products and passes in Creator Hub (Monetization) and paste their IDs here (MON-01).
Config.Products = {
	CashBoost = 0, -- TODO: paste ID from Creator Hub
	InstantRepair = 0, -- TODO: paste ID from Creator Hub
}
Config.Passes = {
	DoubleTips = 0, -- TODO: paste ID from Creator Hub
	GoldenTruck = 0, -- TODO: paste ID from Creator Hub
}

return Config
