-- HUD: team cash, phase + day + countdown, truck health, upgrade shop button.
-- Plan: UI-02 (HUD), UI-06 (shop button)
-- Binds to PlayerGui.Hud and reads replicated workspace attributes:
-- Cash, GameState, StateEndsAt, Day, TruckHp, TruckMaxHp. No remotes needed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UiBind = require(script.Parent.Parent.Lib.UiBind)
local ShopController = require(script.Parent.ShopController)

local HudController = {}

-- TODO(UI): move player-facing text to a LocalizationTable.
local TEXT = {
	Phase = { Ready = "START", Day = "DZIEŃ", Night = "NOC", Shop = "ULEPSZENIA", Results = "WYNIKI" },
	Day = "Dzień %d/%d",
	NoDay = "Dzień -/%d",
	NoTime = "--:--",
	Hp = "%d/%d",
}
local TICK = 0.1

local function formatTime(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

function HudController.Init() end

function HudController.Start()
	local gui = UiBind.screen("Hud")
	if not gui then
		return
	end
	local cashLabel = UiBind.find(gui, "CashPanel/CashLabel")
	local timerPanel = UiBind.find(gui, "TimerPanel")
	local phaseLabel = UiBind.find(gui, "TimerPanel/PhaseLabel")
	local dayLabel = UiBind.find(gui, "TimerPanel/DayLabel")
	local timerLabel = UiBind.find(gui, "TimerPanel/TimerLabel")
	local timerFill = UiBind.find(gui, "TimerPanel/TimerBar/Fill")
	local hpFill = UiBind.find(gui, "TruckHpPanel/HpBar/HpFill")
	local hpLabel = UiBind.find(gui, "TruckHpPanel/HpBar/HpLabel")
	local shopButton = UiBind.find(gui, "ShopButton")

	local dayColor = timerPanel and timerPanel:GetAttribute("DayColor")
	local nightColor = timerPanel and timerPanel:GetAttribute("NightColor")
	local phaseDuration = 0

	local function updateCash()
		if cashLabel then
			cashLabel.Text = UiBind.formatCash(workspace:GetAttribute("Cash") or 0)
		end
	end

	local function updatePhase()
		local state = workspace:GetAttribute("GameState") or "Ready"
		local day = workspace:GetAttribute("Day") or 0
		if phaseLabel then
			phaseLabel.Text = TEXT.Phase[state] or state
		end
		if dayLabel then
			dayLabel.Text = if day > 0
				then string.format(TEXT.Day, day, Config.Run.Days)
				else string.format(TEXT.NoDay, Config.Run.Days)
		end
		local color = if state == "Night" then nightColor else dayColor
		if typeof(color) == "Color3" then
			if phaseLabel then
				phaseLabel.TextColor3 = color
			end
			if timerFill then
				timerFill.BackgroundColor3 = color
			end
		end
		if timerPanel then
			timerPanel:SetAttribute("Phase", state)
		end
		if shopButton then
			shopButton.Visible = state == "Shop"
		end
	end

	local function onEndsAtChanged()
		local endsAt = workspace:GetAttribute("StateEndsAt") or 0
		phaseDuration = if endsAt > 0 then math.max(endsAt - workspace:GetServerTimeNow(), 0.001) else 0
	end

	local function updateTimer()
		local endsAt = workspace:GetAttribute("StateEndsAt") or 0
		if endsAt <= 0 then
			if timerLabel then
				timerLabel.Text = TEXT.NoTime
			end
			UiBind.setFill(timerFill, 1)
			return
		end
		local remaining = endsAt - workspace:GetServerTimeNow()
		if timerLabel then
			timerLabel.Text = formatTime(remaining)
		end
		UiBind.setFill(timerFill, if phaseDuration > 0 then remaining / phaseDuration else 1)
	end

	local function updateHp()
		local hp = workspace:GetAttribute("TruckHp") or 0
		local maxHp = math.max(workspace:GetAttribute("TruckMaxHp") or 1, 1)
		UiBind.setFill(hpFill, hp / maxHp)
		if hpLabel then
			hpLabel.Text = string.format(TEXT.Hp, math.ceil(hp), maxHp)
		end
	end

	if shopButton then
		shopButton.Activated:Connect(ShopController.Toggle)
	end
	workspace:GetAttributeChangedSignal("Cash"):Connect(updateCash)
	workspace:GetAttributeChangedSignal("GameState"):Connect(updatePhase)
	workspace:GetAttributeChangedSignal("Day"):Connect(updatePhase)
	workspace:GetAttributeChangedSignal("StateEndsAt"):Connect(onEndsAtChanged)
	workspace:GetAttributeChangedSignal("TruckHp"):Connect(updateHp)
	workspace:GetAttributeChangedSignal("TruckMaxHp"):Connect(updateHp)

	updateCash()
	updatePhase()
	onEndsAtChanged()
	updateHp()
	while true do
		updateTimer()
		task.wait(TICK)
	end
end

return HudController
