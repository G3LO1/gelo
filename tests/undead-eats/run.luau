-- Client + server integration test of the Undead Eats HUD and upgrade shop:
-- a real run (Ready -> Day -> Night -> Shop -> Day -> ...) with the server services and the
-- HudController / ShopController bound to the UI built from ui/ui-spec.json.
-- Run from the repo root: lune run tests/undead-eats/run

local process = require("@lune/process")
local task = require("@lune/task")

local Mock = require("./mock")

local ROOT = "examples/undead-eats"
local passed, failed = 0, 0

-- A hung test must still report (and flush output) instead of being killed silently.
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
	local deadline = os.clock() + (timeout or 10)
	while os.clock() < deadline do
		if predicate() then
			return true
		end
		task.wait(0.02)
	end
	return false
end

local world = Mock.newWorld(ROOT)
local ws = world.workspace

local function state()
	return ws:GetAttribute("GameState")
end

local function waitState(name: string, timeout: number?): boolean
	return waitUntil(function()
		return state() == name
	end, timeout)
end

-- Fast run: 2 days, short phases. Server and client each load their own copy of the shared
-- modules (like Roblox), so the client's Config gets the same run length.
local Config = world.sharedModule("Config")
local Nights = world.sharedModule("Nights")
world.clientShared("Config").Run.Days = 2
Config.Run.Days = 2
Config.Run.ReadySeconds = 0.3
Config.Run.ShopSeconds = 3
Config.Run.ResultsSeconds = 0.3
for _, night in Nights.Days do
	night.DayDuration = 1.2
	night.NightDuration = 0.6
end

-- Server: only the services this feature touches (no map, customers or stations needed).
local Net = world.sharedModule("Net")
Net.setup()
local services = {}
for _, name in { "DataService", "GameService", "EconomyService", "TruckService", "UpgradeService" } do
	services[name] = world.serverModule(`Services/{name}`)
end
for _, service in services do
	if service.Init then
		service.Init()
	end
end
for _, service in services do
	if service.Start then
		task.spawn(service.Start)
	end
end
local Economy, Truck, Game = services.EconomyService, services.TruckService, services.GameService

-- Client: the player joins with the UI from the spec, then the controllers start.
local player = world.join(1, `{ROOT}/ui/ui-spec.json`)
local hud = player.PlayerGui.Hud
local shop = player.PlayerGui.UpgradeShop
for _, name in { "ShopController", "HudController" } do
	local controller = world.clientModule(`Controllers/{name}`)
	controller.Init()
	task.spawn(controller.Start)
end
task.wait(0.1)

local cards = shop.Panel.ItemList
local function card(id: string)
	return cards[`Upgrade_{id}`]
end
local function click(button)
	button.Activated:Fire()
end

print("Ready")
check(hud.CashPanel.CashLabel.Text == "$0", `cash label $0 (got {hud.CashPanel.CashLabel.Text})`)
check(hud.TruckHpPanel.HpBar.HpLabel.Text == "100/100", "truck HP 100/100")
check(shop.Enabled == false, "shop closed")
check(#world.warnings == 0, "every UI element the controllers need exists (no UiBind warnings)")

print("Day 1")
check(waitState("Day"), "run started")
task.wait(0.15)
check(hud.TimerPanel.PhaseLabel.Text == "DZIEŃ", `phase label (got {hud.TimerPanel.PhaseLabel.Text})`)
check(hud.TimerPanel.DayLabel.Text == "Dzień 1/2", `day label (got {hud.TimerPanel.DayLabel.Text})`)
check(
	string.match(hud.TimerPanel.TimerLabel.Text, "^%d:%d%d$") ~= nil,
	`timer mm:ss (got {hud.TimerPanel.TimerLabel.Text})`
)
check(hud.ShopButton.Visible == false, "shop button hidden during the day")
Economy.Add(500, player, "Gameplay", "Order")
task.wait(0.05)
check(hud.CashPanel.CashLabel.Text == "$500", `cash label follows team cash (got {hud.CashPanel.CashLabel.Text})`)
Economy.Add(1000, player, "Gameplay", "Order")
task.wait(0.05)
check(hud.CashPanel.CashLabel.Text == "$1,500", `thousands separator (got {hud.CashPanel.CashLabel.Text})`)
Truck.Damage(30)
task.wait(0.05)
check(hud.TruckHpPanel.HpBar.HpLabel.Text == "70/100", "HP label after damage")
check(math.abs(hud.TruckHpPanel.HpBar.HpFill.Size.X.Scale - 0.7) < 1e-6, "HP bar fill 70%")
check(world.remote("BuyUpgrade").OnServerInvoke(player, "TruckHp") == "Closed", "shop closed outside the Shop phase")

print("Night 1")
check(waitState("Night"), "night started")
task.wait(0.15)
local nightColor = hud.TimerPanel:GetAttribute("NightColor")
check(hud.TimerPanel.PhaseLabel.Text == "NOC", "phase label NOC")
check(hud.TimerPanel.PhaseLabel.TextColor3 == nightColor, "night color applied")

print("Shop")
check(waitState("Shop"), "shop phase between night 1 and day 2")
check(
	waitUntil(function()
		return shop.Enabled
	end, 1),
	"shop opens by itself"
)
check(hud.ShopButton.Visible, "shop button visible")
check(card("TruckHp").LevelLabel.Text == "Poz. 0/5", "level label")
check(card("TruckHp").BuyButton.Text == "$150", "TruckHp price $150")
check(card("ExtraSlot").LevelLabel.Text == "Poz. 0/3", "ExtraSlot max level from Upgrades (3)")
check(card("TruckHp").BuyButton.Interactable == true, "affordable button is interactable")

click(card("TruckHp").BuyButton)
check(
	waitUntil(function()
		return ws:GetAttribute("Upgrade_TruckHp") == 1
	end, 1),
	"click -> server bought TruckHp level 1"
)
task.wait(0.05)
check(hud.CashPanel.CashLabel.Text == "$1,350", "cash charged (1500 - 150)")
check(ws:GetAttribute("TruckMaxHp") == 125 and ws:GetAttribute("TruckHp") == 95, "max HP +25 and healed by 25")
check(hud.TruckHpPanel.HpBar.HpLabel.Text == "95/125", "HUD shows new HP")
check(
	card("TruckHp").LevelLabel.Text == "Poz. 1/5" and card("TruckHp").BuyButton.Text == "$250",
	"card shows level 1 and next price"
)
local event = world.analytics[#world.analytics]
check(
	event.amount == 150 and event.balance == 1350 and event.sku == "Upgrade_TruckHp",
	"analytics: amount 150 then ending balance 1350"
)

click(card("CookSpeed").BuyButton)
check(
	waitUntil(function()
		return ws:GetAttribute("Upgrade_CookSpeed") == 1
	end, 1),
	"CookSpeed bought"
)
check(math.abs(ws:GetAttribute("CookSpeed") - 1 / 0.88) < 1e-6, "cook speed multiplier 1/0.88")

for _ = 1, 5 do -- spend down to something that can't afford ExtraSlot ($300)
	if Economy.Get() >= 300 then
		Economy.Spend(Economy.Get() - 250, player, "Gameplay", "Test")
	end
end
task.wait(0.05)
check(card("ExtraSlot").BuyButton.Interactable == false, "unaffordable button disabled")
check(card("ExtraSlot").BuyButton.BackgroundTransparency > 0, "unaffordable button dimmed")
local before = Economy.Get()
check(world.remote("BuyUpgrade").OnServerInvoke(player, "ExtraSlot") == "TooPoor", "server refuses when too poor")
check(Economy.Get() == before, "no money taken")
check(world.remote("BuyUpgrade").OnServerInvoke(player, "Nope") == nil, "unknown upgrade id rejected by Guard")
check(world.remote("BuyUpgrade").OnServerInvoke(player, 0 / 0) == nil, "NaN rejected by Guard")

print("Day 2")
check(waitState("Day", 5), "day 2 started")
task.wait(0.15)
check(shop.Enabled == false, "shop closes by itself")
check(hud.ShopButton.Visible == false, "shop button hidden again")
check(hud.TimerPanel.DayLabel.Text == "Dzień 2/2", "day label 2/2")

print("Truck destroyed")
Truck.Damage(10000)
check(waitState("Results", 3), "run lost -> Results")
check(Game.Run.Reason == "TruckDestroyed", "loss reason TruckDestroyed")
check(waitState("Ready", 3), "back to Ready")
task.wait(0.15)
check(ws:GetAttribute("Upgrade_TruckHp") == 0 and ws:GetAttribute("CookSpeed") == 1, "upgrades reset for the new run")
check(ws:GetAttribute("TruckMaxHp") == 100 and ws:GetAttribute("TruckHp") == 100, "truck HP reset")
check(hud.CashPanel.CashLabel.Text == "$0", "cash reset on HUD")
check(hud.TruckHpPanel.HpBar.HpLabel.Text == "100/100", "HP reset on HUD")
check(card("TruckHp").LevelLabel.Text == "Poz. 0/5", "shop levels reset")

check(#world.warnings == 0, "no warnings during the run")

print(`\n{passed} passed, {failed} failed`)
process.exit(if failed == 0 then 0 else 1)
