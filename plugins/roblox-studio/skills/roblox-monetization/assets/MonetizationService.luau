-- Wires the generated catalog (ReplicatedStorage.Shared.Monetization, written by monetize.py) to the
-- template's PurchaseService: grants developer products, answers pass perks and multipliers, and tells
-- the buyer's client to show the purchase popup (remote "PurchaseResult", add it to Net.Events).
--
-- MonetizationService.Owns(player, "VIP")              -> boolean, game passes (cached, may yield once)
-- MonetizationService.Multiplier(player, "Cash")       -> product of every owned multiplier pass for the stat, 1 if none
-- MonetizationService.OnProduct("ServerLuck", handler) -> handler(player, data) for grant type "handler"; must not yield,
--                                                         change only `data` (or call task.defer for world effects)
-- MonetizationService.OnPass("VIP", callback)          -> callback(player) right after a purchase in this server
-- Owned passes are also mirrored to player attributes ("OwnsVIP" = true) for UI and other systems.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Monetization)
local Net = require(ReplicatedStorage.Shared.Net)
local PurchaseService = require(script.Parent.PurchaseService)

local MonetizationService = {}

type Item = Monetization.Item

local productHandlers: { [string]: (Player, any) -> () } = {}
local passCallbacks: { [string]: { (Player) -> () } } = {}
local passById: { [number]: Item } = {}

local function item(key: string, kind: string): Item
	local found = Monetization.Items[key]
	assert(found, `[Monetization] unknown item "{key}": add it to monetization.json and run monetize.py sync`)
	assert(found.Kind == kind, `[Monetization] "{key}" is a {found.Kind}, not a {kind}`)
	return found
end

local function notify(player: Player, key: string)
	task.defer(function()
		if player.Parent then
			Net.fireClient(player, "PurchaseResult", key)
		end
	end)
end

local function productGrant(product: Item): (Player, any) -> ()
	return function(player, data)
		local grant = product.Grant
		if grant.type == "currency" then
			local field = grant.field :: string
			assert(type(data[field]) == "number", `{product.Key}: data.{field} is not a number (Config.DefaultData)`)
			data[field] += grant.amount :: number
		else
			local handler = productHandlers[product.Key]
			-- An error here leaves the receipt unprocessed; Roblox retries it later, nothing is lost.
			assert(handler, `{product.Key}: no handler registered with MonetizationService.OnProduct`)
			handler(player, data)
		end
		notify(player, product.Key)
	end
end

function MonetizationService.Owns(player: Player, key: string): boolean
	local pass = item(key, "Pass")
	if pass.Id == 0 then
		return false
	end
	return PurchaseService.OwnsPass(player, pass.Id)
end

function MonetizationService.Multiplier(player: Player, stat: string): number
	local multiplier = 1
	for key, entry in Monetization.Items do
		local grant = entry.Grant
		if entry.Kind == "Pass" and grant.type == "multiplier" and grant.stat == stat then
			if MonetizationService.Owns(player, key) then
				multiplier *= grant.value :: number
			end
		end
	end
	return multiplier
end

function MonetizationService.OnProduct(key: string, handler: (Player, any) -> ())
	local product = item(key, "Product")
	assert(product.Grant.type == "handler", `{key} grants {product.Grant.type}; only "handler" products take OnProduct`)
	assert(productHandlers[key] == nil, `{key} already has a handler`)
	productHandlers[key] = handler
end

function MonetizationService.OnPass(key: string, callback: (Player) -> ())
	item(key, "Pass")
	passCallbacks[key] = passCallbacks[key] or {}
	table.insert(passCallbacks[key], callback)
end

local function mirrorPasses(player: Player)
	for key, entry in Monetization.Items do
		if entry.Kind == "Pass" and entry.Id ~= 0 and MonetizationService.Owns(player, key) then
			player:SetAttribute(`Owns{key}`, true)
		end
	end
end

function MonetizationService.Init()
	local missing = {}
	for key, entry in Monetization.Items do
		if entry.Id == 0 then
			table.insert(missing, key)
		elseif entry.Kind == "Product" then
			PurchaseService.RegisterProduct(entry.Id, productGrant(entry))
		else
			passById[entry.Id] = entry
		end
	end
	if #missing > 0 then
		table.sort(missing)
		warn(`[Monetization] not created yet (run monetize.py sync): {table.concat(missing, ", ")}`)
	end
end

function MonetizationService.Start()
	PurchaseService.OnPassPurchased(function(player, passId)
		local pass = passById[passId]
		if not pass then
			return
		end
		player:SetAttribute(`Owns{pass.Key}`, true)
		notify(player, pass.Key)
		for _, callback in passCallbacks[pass.Key] or {} do
			task.spawn(callback, player)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		mirrorPasses(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(mirrorPasses, player)
	end
end

return MonetizationService
