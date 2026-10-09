-- Upgrade shop window: shows levels and prices, sends purchase intents, gives feedback.
-- Plan: UI-06 (upgrade shop), SYS-11 (client side)
-- Binds to PlayerGui.UpgradeShop (cards = children of Panel/ItemList with an UpgradeId attribute).
-- Opens by itself when the Shop phase starts and closes when it ends; the HUD button toggles it.
--
-- ShopController.Open() / Close() / Toggle() / IsOpen()

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local UiBind = require(script.Parent.Parent.Lib.UiBind)

local ShopController = {}

-- TODO(UI): move player-facing text to a LocalizationTable.
local TEXT = {
	Level = "Poz. %d/%d",
	Max = "MAX",
	TooPoor = "ZA MAŁO!",
	Closed = "ZAMKNIĘTE",
}
local DIMMED = 0.45
local FEEDBACK_SECONDS = 0.9

type Card = {
	id: string,
	frame: GuiObject,
	levelLabel: TextLabel?,
	buyButton: TextButton?,
	busy: boolean,
	feedbackUntil: number,
}

local gui: ScreenGui? = nil
local panel: GuiObject? = nil
local cashLabel: TextLabel? = nil
local cards: { Card } = {}

local function cash(): number
	return workspace:GetAttribute("Cash") or 0
end

local function refreshCard(card: Card)
	local def = Upgrades.Defs[card.id]
	local level = workspace:GetAttribute(Upgrades.attribute(card.id)) or 0
	if card.levelLabel then
		card.levelLabel.Text = string.format(TEXT.Level, level, def.MaxLevel)
	end
	local button = card.buyButton
	if not button or os.clock() < card.feedbackUntil then
		return
	end
	local cost = Upgrades.nextCost(card.id, level)
	local canBuy = cost ~= nil and cash() >= cost and workspace:GetAttribute("GameState") == "Shop"
	button.Text = if cost then UiBind.formatCash(cost) else TEXT.Max
	button.Interactable = canBuy and not card.busy
	button.BackgroundTransparency = if canBuy then 0 else DIMMED
	button.TextTransparency = if canBuy then 0 else DIMMED * 0.6
end

local function refresh()
	if cashLabel then
		cashLabel.Text = UiBind.formatCash(cash())
	end
	for _, card in cards do
		refreshCard(card)
	end
end

local function flash(card: Card, text: string)
	local button = card.buyButton
	if not button then
		return
	end
	card.feedbackUntil = os.clock() + FEEDBACK_SECONDS
	button.Text = text
	task.delay(FEEDBACK_SECONDS, refreshCard, card)
end

local function buy(card: Card)
	if card.busy then
		return
	end
	card.busy = true
	refreshCard(card)
	local result = Net.invoke("BuyUpgrade", card.id)
	card.busy = false
	if result == "Bought" then
		UiBind.pop(card.frame, 0.9)
	elseif result == "TooPoor" then
		flash(card, TEXT.TooPoor)
	elseif result == "Closed" then
		flash(card, TEXT.Closed)
	end
	refresh()
end

function ShopController.IsOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function ShopController.Open()
	if not gui or gui.Enabled then
		return
	end
	refresh()
	gui.Enabled = true
	UiBind.pop(panel)
	if UserInputService.GamepadEnabled and cards[1] and cards[1].buyButton then
		GuiService.SelectedObject = cards[1].buyButton
	end
end

function ShopController.Close()
	if not gui or not gui.Enabled then
		return
	end
	gui.Enabled = false
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

function ShopController.Toggle()
	if ShopController.IsOpen() then
		ShopController.Close()
	else
		ShopController.Open()
	end
end

function ShopController.Init() end

function ShopController.Start()
	gui = UiBind.screen("UpgradeShop")
	if not gui then
		return
	end
	gui.Enabled = false
	panel = UiBind.find(gui, "Panel")
	cashLabel = UiBind.find(gui, "Panel/Header/CashChip/CashLabel")

	local itemList = UiBind.find(gui, "Panel/ItemList")
	for _, frame in if itemList then itemList:GetChildren() else {} do
		local id = frame:GetAttribute("UpgradeId")
		if id and Upgrades.Defs[id] then
			local card: Card = {
				id = id,
				frame = frame,
				levelLabel = UiBind.find(frame, "LevelLabel"),
				buyButton = UiBind.find(frame, "BuyButton"),
				busy = false,
				feedbackUntil = 0,
			}
			table.insert(cards, card)
			if card.buyButton then
				card.buyButton.Activated:Connect(function()
					buy(card)
				end)
			end
		elseif id then
			warn(`[ShopController] card {frame.Name} has unknown UpgradeId "{id}"`)
		end
	end
	table.sort(cards, function(a, b)
		return (a.frame :: any).LayoutOrder < (b.frame :: any).LayoutOrder
	end)

	local closeButton = UiBind.find(gui, "Panel/Header/CloseButton")
	if closeButton then
		closeButton.Activated:Connect(ShopController.Close)
	end

	workspace:GetAttributeChangedSignal("Cash"):Connect(refresh)
	for _, id in Upgrades.Ids do
		workspace:GetAttributeChangedSignal(Upgrades.attribute(id)):Connect(refresh)
	end
	local function onState()
		if workspace:GetAttribute("GameState") == "Shop" then
			ShopController.Open()
		else
			ShopController.Close()
		end
		refresh()
	end
	workspace:GetAttributeChangedSignal("GameState"):Connect(onState)
	onState()
end

return ShopController
