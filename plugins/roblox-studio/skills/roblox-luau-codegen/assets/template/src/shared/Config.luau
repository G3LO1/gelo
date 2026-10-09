-- Game-wide settings shared by server and client. Keep secrets and prices that the
-- server enforces here too: the client can read them, but only the server trusts them.

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
	-- [2] = function(data) data.Gems = data.Gems or 0 end,
	Migrations = {} :: { [number]: (data: any) -> () },
}

-- Every new field added here is filled in for existing players on load.
Config.DefaultData = {
	Version = 1,
	Coins = 0,
	Inventory = {},
	PurchaseHistory = {},
}

-- Create products and passes in Creator Hub (Monetization) and paste their IDs here.
Config.Products = {}
Config.Passes = {}

return Config
