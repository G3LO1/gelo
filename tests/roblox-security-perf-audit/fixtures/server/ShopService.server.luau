-- expect: SEC-CLIENT-VALUE, SEC-CLIENT-VALUE, SEC-CLIENT-AMOUNT, SEC-INVOKE-CLIENT, SEC-NAME-CHECK, DATA-SETASYNC, DATA-NO-PCALL, DATA-NO-PCALL, PERF-SERVER-TWEEN, PERF-DEPRECATED-SCHED, PERF-DEPRECATED-SCHED, PURCHASE-MULTI-RECEIPT
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local store = DataStoreService:GetDataStore("Coins")

ReplicatedStorage.Buy.OnServerEvent:Connect(function(player, itemId: string, price: number)
	player.leaderstats.Coins.Value -= price
end)

ReplicatedStorage.Damage.OnServerInvoke = function(player, target, damage, amount)
	return target.Humanoid:TakeDamage(damage * amount)
end

game:GetService("Players").PlayerAdded:Connect(function(player)
	if player.Name == "Builderman" then
		player:SetAttribute("Admin", true)
	end
	local coins = store:GetAsync(player.UserId)
	store:SetAsync(player.UserId, coins or 0)
	local answer = ReplicatedStorage.Ask:InvokeClient(player)
	TweenService:Create(workspace.Door, TweenInfo.new(1), { Transparency = 1 }):Play()
	wait(1)
	spawn(function() end)
end)

MarketplaceService.ProcessReceipt = function(receipt)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
