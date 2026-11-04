-- Client side of the generated catalog: purchase prompts, live prices, "Owned" state and the
-- popup shown after the server granted a purchase (remote "PurchaseResult").
--
-- ShopController.Prompt("DoubleCash")                  open Roblox's purchase prompt
-- ShopController.GetPrice("DoubleCash")                -> Robux the local player pays, or nil (yields, cached)
-- ShopController.Owns("DoubleCash")                    -> boolean, passes (attribute mirrored by the server)
-- ShopController.Bind(button, "DoubleCash", label?)    click prompts; label shows the price or "Owned"
-- ShopController.Build(parent)                         -> a ready shop grid (icon, name, price) for every item on sale
-- ShopController.OnPurchased(callback)                 callback(item) after the server granted a purchase
-- ShopController.ShowPopup = false                     turn the default popup off when your UI has its own

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Monetization = require(ReplicatedStorage.Shared.Monetization)
local Net = require(ReplicatedStorage.Shared.Net)

local ShopController = {}
ShopController.ShowPopup = true

type Item = Monetization.Item

local ROBUX = utf8.char(0xE002) -- Roblox renders this private-use glyph as the Robux icon
local POPUP_SECONDS = 2.5

local player = Players.LocalPlayer
local prices: { [string]: number } = {}
local callbacks: { (Item) -> () } = {}
local popup: Frame? = nil

local function get(key: string): Item
	local found = Monetization.Items[key]
	assert(found, `[Shop] unknown item "{key}"`)
	return found
end

function ShopController.Prompt(key: string)
	local entry = get(key)
	if entry.Id == 0 or not entry.ForSale then
		warn(`[Shop] {key} is not on sale yet (run monetize.py sync)`)
		return
	end
	if entry.Kind == "Pass" then
		if ShopController.Owns(key) then
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, entry.Id)
	else
		MarketplaceService:PromptProductPurchase(player, entry.Id)
	end
end

function ShopController.GetPrice(key: string): number?
	if prices[key] then
		return prices[key]
	end
	local entry = get(key)
	if entry.Id == 0 then
		return nil
	end
	local infoType = if entry.Kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
	local ok, info = pcall(MarketplaceService.GetProductInfoAsync, MarketplaceService, entry.Id, infoType)
	if not ok or type(info) ~= "table" or type(info.PriceInRobux) ~= "number" then
		return nil -- not cached: the next call retries
	end
	prices[key] = info.PriceInRobux
	return info.PriceInRobux
end

function ShopController.Owns(key: string): boolean
	return get(key).Kind == "Pass" and player:GetAttribute(`Owns{key}`) == true
end

function ShopController.Bind(button: GuiButton, key: string, label: TextLabel?)
	local entry = get(key)
	local target = label or (button:IsA("TextButton") and button :: any) or nil
	local function refresh()
		if not target then
			return
		end
		if ShopController.Owns(key) then
			target.Text = "Owned"
			return
		end
		local price = ShopController.GetPrice(key)
		target.Text = if price then `{ROBUX} {price}` else "..."
	end
	button.Activated:Connect(function()
		ShopController.Prompt(key)
	end)
	if entry.Kind == "Pass" then
		player:GetAttributeChangedSignal(`Owns{key}`):Connect(refresh)
	end
	task.spawn(refresh)
end

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for prop, value in props do
		instance[prop] = value
	end
	instance.Parent = parent
	return instance
end

function ShopController.Build(parent: Instance): Frame
	local grid = new("ScrollingFrame", {
		Name = "MonetizationShop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
	}, parent)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(150, 190),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, grid)
	for key, entry in Monetization.Items do
		if entry.Id == 0 or not entry.ForSale then
			continue
		end
		local card = new("Frame", {
			Name = key,
			LayoutOrder = entry.Order,
			BackgroundColor3 = Color3.fromRGB(30, 32, 44),
		}, grid)
		new("UICorner", { CornerRadius = UDim.new(0, 12) }, card)
		new("ImageLabel", {
			Name = "Icon",
			Image = entry.Icon,
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, -48, 0, 10),
			Size = UDim2.fromOffset(96, 96),
		}, card)
		new("TextLabel", {
			Name = "Title",
			Text = entry.Name,
			TextScaled = true,
			Font = Enum.Font.GothamBold,
			TextColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 8, 0, 110),
			Size = UDim2.new(1, -16, 0, 24),
		}, card)
		local buy = new("TextButton", {
			Name = "Buy",
			Text = "...",
			TextScaled = true,
			Font = Enum.Font.GothamBold,
			TextColor3 = Color3.new(1, 1, 1),
			BackgroundColor3 = Color3.fromRGB(0, 176, 111),
			Position = UDim2.new(0, 12, 1, -48),
			Size = UDim2.new(1, -24, 0, 38), -- 38 px+ keeps it tappable on phones
		}, card)
		new("UICorner", { CornerRadius = UDim.new(0, 10) }, buy)
		ShopController.Bind(buy, key)
	end
	return grid
end

function ShopController.OnPurchased(callback: (Item) -> ())
	table.insert(callbacks, callback)
end

local function getPopup(): Frame
	if popup then
		return popup
	end
	local gui = new("ScreenGui", { Name = "PurchasePopup", ResetOnSpawn = false, DisplayOrder = 50 })
	local frame = new("Frame", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -120),
		Size = UDim2.fromOffset(320, 84),
		BackgroundColor3 = Color3.fromRGB(24, 26, 36),
		Visible = false,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 14) }, frame)
	new("UIStroke", { Color = Color3.fromRGB(0, 176, 111), Thickness = 2 }, frame)
	new("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(64, 64),
	}, frame)
	new("TextLabel", {
		Name = "Message",
		TextScaled = true,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(84, 14),
		Size = UDim2.new(1, -96, 1, -28),
	}, frame)
	gui.Parent = player:WaitForChild("PlayerGui")
	popup = frame
	return frame
end

local showing = 0

local function showPopup(entry: Item)
	local frame = getPopup()
	local icon = frame:FindFirstChild("Icon") :: ImageLabel
	local message = frame:FindFirstChild("Message") :: TextLabel
	icon.Image = entry.Icon
	message.Text = `Purchased {entry.Name}!`
	frame.Visible = true
	showing += 1
	local mine = showing
	local info = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(frame, info, { Position = UDim2.new(0.5, 0, 0, 24) }):Play()
	task.delay(POPUP_SECONDS, function()
		if mine ~= showing then
			return -- a newer popup took over
		end
		local hide = TweenService:Create(frame, TweenInfo.new(0.2), { Position = UDim2.new(0.5, 0, 0, -120) })
		hide.Completed:Connect(function()
			if mine == showing then
				frame.Visible = false
			end
		end)
		hide:Play()
	end)
end

function ShopController.Init() end

function ShopController.Start()
	Net.on("PurchaseResult", function(key: string)
		local entry = Monetization.Items[key]
		if not entry then
			return
		end
		if ShopController.ShowPopup then
			showPopup(entry)
		end
		for _, callback in callbacks do
			task.spawn(callback, entry)
		end
	end)
end

return ShopController
