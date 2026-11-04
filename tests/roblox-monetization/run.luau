-- Client + server test of the roblox-monetization runtime: the Monetization.luau module written by
-- monetize.py (from test_sync.py), MonetizationService on top of the codegen template's
-- PurchaseService/DataService, and ShopController (prompts, prices, Owned state, shop grid, popup).
-- Usage: lune run tests/roblox-monetization/run <workdir containing Monetization.luau>

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Mock = require("../undead-eats/mock")

local TEMPLATE = "plugins/roblox-studio/skills/roblox-luau-codegen/assets/template"
local SKILL = "plugins/roblox-studio/skills/roblox-monetization"
local WORK = assert(process.args[1], "usage: lune run tests/roblox-monetization/run <workdir>")
local ROOT = `{WORK}/project`
local ROBUX = utf8.char(0xE002)
local Enum = roblox.Enum

local passed, failed = 0, 0

task.delay(60, function()
	print(`\nTIMEOUT after 60 s: {passed} passed, {failed} failed so far`)
	process.exit(2)
end)

local function check(condition: any, message: string)
	if condition then
		passed += 1
		print(`  ok   {message}`)
	else
		failed += 1
		print(`  FAIL {message}`)
	end
end

local function waitUntil(predicate: () -> boolean, timeout: number?): boolean
	local deadline = os.clock() + (timeout or 5)
	while os.clock() < deadline do
		if predicate() then
			return true
		end
		task.wait(0.02)
	end
	return false
end

-- Project: template + skill assets + generated catalog -----------------------------

if fs.isDir(ROOT) then
	fs.removeDir(ROOT)
end
fs.copy(`{TEMPLATE}/src`, `{ROOT}/src`)
fs.copy(`{SKILL}/assets/MonetizationService.luau`, `{ROOT}/src/server/Services/MonetizationService.luau`)
fs.copy(`{SKILL}/assets/ShopController.luau`, `{ROOT}/src/client/Controllers/ShopController.luau`)
fs.copy(`{WORK}/Monetization.luau`, `{ROOT}/src/shared/Monetization.luau`)

local world = Mock.newWorld(ROOT)

-- MarketplaceService ------------------------------------------------------------------

local ownedPasses: { [string]: boolean } = {}
local prompts = {}
local prices = {}
local marketplace = {
	PromptGamePassPurchaseFinished = Mock.Signal.new(),
	UserOwnsGamePassAsync = function(_, userId, passId)
		task.wait()
		return ownedPasses[`{userId}:{passId}`] == true
	end,
	PromptGamePassPurchase = function(_, player, passId)
		table.insert(prompts, { kind = "Pass", player = player, id = passId })
	end,
	PromptProductPurchase = function(_, player, productId)
		table.insert(prompts, { kind = "Product", player = player, id = productId })
	end,
	GetProductInfoAsync = function(_, id, infoType)
		task.wait()
		return { PriceInRobux = prices[id], InfoType = infoType }
	end,
}
world.services.MarketplaceService = marketplace

-- Boot ----------------------------------------------------------------------------------

local Catalog = world.sharedModule("Monetization").Items
local ids = {}
for key, item in Catalog do
	ids[key] = item.Id
end
prices[ids.StarterPack] = 49
prices[ids.DoubleCash] = 199
prices[ids.BiggerSize] = 149
prices[ids.ServerEvent] = 99

local Config = world.sharedModule("Config")
Config.DefaultData.Cash = 0

local Net = world.sharedModule("Net")
table.insert(Net.Events, "PurchaseResult")
Net.setup()

local services = {}
for _, name in { "DataService", "PurchaseService", "MonetizationService" } do
	services[name] = world.serverModule(`Services/{name}`)
end
for _, service in services do
	service.Init()
end
for _, service in services do
	task.spawn(service.Start)
end
local DataService = services.DataService
local Monetization = services.MonetizationService

local player = world.join(77)
ownedPasses[`77:{ids.BiggerSize}`] = true
DataService.WaitFor(player, 5)

local Shop = world.clientModule("Controllers/ShopController")
Shop.Init()
task.spawn(Shop.Start)
task.wait(0.05)

local function receipt(key: string, purchaseId: string)
	return marketplace.ProcessReceipt({ PlayerId = 77, ProductId = ids[key], PurchaseId = purchaseId })
end

local popupFrame = function()
	local gui = player.PlayerGui:FindFirstChild("PurchasePopup")
	return gui and gui:FindFirstChild("Toast")
end

-- Tests --------------------------------------------------------------------------------

print("catalog")
check(Catalog.DoubleCash.Kind == "Pass" and ids.DoubleCash > 0, "generated module loads in the game")
check(string.match(Catalog.DoubleCash.Icon, "^rbxassetid://%d+$") ~= nil, "icon is an rbxassetid")

print("passes")
check(waitUntil(function()
	return player:GetAttribute("OwnsBiggerSize") == true
end), "owned pass mirrored to a player attribute on join")
check(player:GetAttribute("OwnsDoubleCash") == nil, "unowned pass not mirrored")
check(Monetization.Owns(player, "BiggerSize") == true, "Owns(BiggerSize)")
check(Monetization.Multiplier(player, "Size") == 1.25, "Size multiplier 1.25 from the +25% pass")
check(Monetization.Multiplier(player, "Cash") == 1, "Cash multiplier 1 before buying 2x Cash")

local passCallback = nil
Monetization.OnPass("DoubleCash", function(buyer)
	passCallback = buyer
end)
marketplace.PromptGamePassPurchaseFinished:Fire(player, ids.DoubleCash, true)
check(waitUntil(function()
	return passCallback == player
end), "OnPass callback after purchase")
check(Monetization.Multiplier(player, "Cash") == 2, "Cash multiplier 2 right after buying (no rejoin)")
check(player:GetAttribute("OwnsDoubleCash") == true, "new pass mirrored to the attribute")
check(waitUntil(function()
	local frame = popupFrame()
	return frame ~= nil and frame.Visible and frame.Message.Text == "Purchased 2x Cash!"
end), "client popup: Purchased 2x Cash!")
check(popupFrame().Icon.Image == Catalog.DoubleCash.Icon, "popup shows the pass icon")
marketplace.PromptGamePassPurchaseFinished:Fire(player, 123456789, true)
check(true, "unknown pass purchase ignored without error")

print("developer products")
local results = world.remote("PurchaseResult").clientFires
local before = #results
check(receipt("StarterPack", "r-1") == Enum.ProductPurchaseDecision.PurchaseGranted, "StarterPack receipt granted")
check(DataService.Get(player).Cash == 5000, "currency grant: +5000 Cash")
check(receipt("StarterPack", "r-1") == Enum.ProductPurchaseDecision.PurchaseGranted, "retried receipt acknowledged")
check(DataService.Get(player).Cash == 5000, "not granted twice")
check(waitUntil(function()
	return #results == before + 1 and results[#results].args[1] == "StarterPack"
end), "PurchaseResult sent once to the buyer")
check(waitUntil(function()
	return popupFrame().Message.Text == "Purchased Starter Pack!"
end), "popup for the product")

check(receipt("ServerEvent", "r-2") == Enum.ProductPurchaseDecision.NotProcessedYet, "handler product without a handler is not acknowledged")
local events = 0
Monetization.OnProduct("ServerEvent", function(_buyer, _data)
	events += 1
end)
check(receipt("ServerEvent", "r-2") == Enum.ProductPurchaseDecision.PurchaseGranted, "granted once the handler exists (Roblox retry)")
check(events == 1, "handler ran once")
check(not pcall(Monetization.OnProduct, "StarterPack", function() end), "OnProduct refused for a currency product")
check(not pcall(Monetization.Owns, player, "StarterPack"), "Owns refused for a product")
check(not pcall(Monetization.Owns, player, "Nope"), "unknown key errors loudly")

print("client shop")
task.wait(0.05)
check(Shop.GetPrice("DoubleCash") == 199, "price read from GetProductInfoAsync")
check(Shop.Owns("DoubleCash") == true and Shop.Owns("StarterPack") == false, "Owns from the attribute")
Shop.Prompt("StarterPack")
check(prompts[#prompts].kind == "Product" and prompts[#prompts].id == ids.StarterPack, "Prompt(product) -> PromptProductPurchase")
local count = #prompts
Shop.Prompt("DoubleCash")
check(#prompts == count, "owned pass is not prompted again")

local holder = Mock.Instance.new("Frame", "ShopHolder")
local grid = Shop.Build(holder)
local cards = {}
for _, child in grid:GetChildren() do
	if child.ClassName == "Frame" then
		cards[child.Name] = child
	end
end
check(cards.StarterPack and cards.DoubleCash and cards.BiggerSize and cards.ServerEvent, "Build: one card per item")
check(cards.DoubleCash.LayoutOrder == 2 and cards.StarterPack.Icon.Image == Catalog.StarterPack.Icon, "cards ordered, with icons")
check(waitUntil(function()
	return cards.StarterPack.Buy.Text == `{ROBUX} 49` and cards.DoubleCash.Buy.Text == "Owned"
end), "card shows the Robux price, or Owned")
cards.ServerEvent.Buy.Activated:Fire()
check(waitUntil(function()
	return prompts[#prompts].id == ids.ServerEvent
end), "card button prompts the purchase")

print("not synced yet")
local unsynced = world.clientShared("Monetization").Items
unsynced.StarterPack.Id = 0
local warnings = #world.warnings
Shop.Prompt("StarterPack")
check(#world.warnings == warnings + 1 and string.find(world.warnings[#world.warnings], "monetize.py sync") ~= nil, "Id 0: warns instead of prompting")

print()
print(`{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
