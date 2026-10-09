-- Developer products and passes. Product grants are idempotent: each PurchaseId is
-- stored in the player's data and only acknowledged to Roblox after a successful save.
--
-- PurchaseService.RegisterProduct(Config.Products.Coins100, function(player, data)
--     data.Coins += 100
-- end)
-- PurchaseService.OwnsPass(player, Config.Passes.VIP) -> boolean
-- PurchaseService.OnPassPurchased(function(player, passId) ... end)

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)

local PurchaseService = {}

local HISTORY_LIMIT = 50

local productHandlers: { [number]: (Player, any) -> () } = {}
local passCache: { [Player]: { [number]: boolean } } = {}
local passCallbacks: { (Player, number) -> () } = {}

-- handler mutates `data` to grant the product. It must not yield; validate before changing anything.
function PurchaseService.RegisterProduct(productId: number, handler: (player: Player, data: any) -> ())
	assert(productHandlers[productId] == nil, `Product {productId} already has a handler`)
	productHandlers[productId] = handler
end

local function processReceipt(receipt): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox retries when they join again
	end
	local data = DataService.WaitFor(player, 15)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if table.find(data.PurchaseHistory, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted, earlier save may have failed
	end
	local handler = productHandlers[receipt.ProductId]
	if not handler then
		warn(`[PurchaseService] No handler for product {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, updated = pcall(DataService.Update, player, function(playerData)
		handler(player, playerData)
		table.insert(playerData.PurchaseHistory, receipt.PurchaseId)
		while #playerData.PurchaseHistory > HISTORY_LIMIT do
			table.remove(playerData.PurchaseHistory, 1)
		end
	end)
	if not ok or updated ~= true then
		warn(`[PurchaseService] Granting product {receipt.ProductId} failed: {updated}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not DataService.Save(player) then
		-- Granted in memory and recorded; Roblox will retry and the history check above acknowledges it.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function PurchaseService.OwnsPass(player: Player, passId: number): boolean
	local cache = passCache[player]
	if not cache then
		cache = {}
		passCache[player] = cache
	end
	if cache[passId] ~= nil then
		return cache[passId]
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
	if not ok then
		warn(`[PurchaseService] Pass check failed for {player.UserId}: {owns}`)
		return false -- not cached, so the next call retries
	end
	cache[passId] = owns
	return owns
end

function PurchaseService.OnPassPurchased(callback: (Player, number) -> ())
	table.insert(passCallbacks, callback)
end

function PurchaseService.Init() end

function PurchaseService.Start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local cache = passCache[player]
		if cache then
			cache[passId] = true
		end
		for _, callback in passCallbacks do
			task.spawn(callback, player, passId)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
	end)
end

return PurchaseService
