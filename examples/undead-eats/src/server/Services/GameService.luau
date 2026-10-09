-- Run state machine: Ready -> (Day -> Night -> Shop) x Config.Run.Days -> Results -> Ready
-- (no Shop after the last night).
-- Plan: SYS-02, SYS-11 (Shop phase)
--
-- State replicates through workspace attributes (no remote needed):
--   GameState ("Ready" | "Day" | "Night" | "Shop" | "Results"), StateEndsAt (GetServerTimeNow, 0 = untimed), Day (0 when idle)
--
-- GameService.GetState()            -> state name
-- GameService.Run                   -> { Day, Served, Lost, Earned, Result, Reason } for the current/last run
-- GameService.OnStateChanged(cb)    -> cb(state, day); register in Init so no change is missed
-- GameService.Lose(reason)          -> ends the run as lost (truck destroyed, SYS-07); ignored outside a run
-- GameService.SkipNight()           -> ends the current night early (all waves cleared, SYS-06)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Nights = require(ReplicatedStorage.Shared.Nights)
local DataService = require(script.Parent.DataService)

local GameService = {}

export type RunInfo = {
	Day: number,
	Served: number,
	Lost: number,
	Earned: number,
	Result: string?,
	Reason: string?,
}

local state = "Ready"
local callbacks: { (string, number) -> () } = {}
local lostReason: string? = nil
local skipRequested = false

GameService.Run = { Day = 0, Served = 0, Lost = 0, Earned = 0, Result = nil, Reason = nil } :: RunInfo

local function resetRun()
	local run = GameService.Run
	run.Day, run.Served, run.Lost, run.Earned, run.Result, run.Reason = 0, 0, 0, 0, nil, nil
	lostReason = nil
	skipRequested = false
end

local function setState(newState: string, duration: number)
	state = newState
	workspace:SetAttribute("GameState", newState)
	workspace:SetAttribute("Day", GameService.Run.Day)
	workspace:SetAttribute("StateEndsAt", if duration > 0 then workspace:GetServerTimeNow() + duration else 0)
	for _, callback in callbacks do
		task.spawn(callback, newState, GameService.Run.Day)
	end
end

-- Waits `duration` seconds; returns false as soon as abortCheck() is true.
local function waitTimed(duration: number, abortCheck: () -> boolean): boolean
	local deadline = os.clock() + duration
	while os.clock() < deadline do
		if abortCheck() then
			return false
		end
		task.wait(0.25)
	end
	return not abortCheck()
end

local function enoughPlayers(): boolean
	return #Players:GetPlayers() >= Config.Run.MinPlayers
end

local function phaseAborted(): boolean
	return lostReason ~= nil or skipRequested or not enoughPlayers()
end

local function recordStats(won: boolean, day: number)
	for _, player in Players:GetPlayers() do
		DataService.Update(player, function(data)
			local stats = data.Stats
			if won then
				stats.RunsWon += 1
			else
				stats.RunsLost += 1
			end
			stats.BestDay = math.max(stats.BestDay, day)
		end)
	end
end

-- Returns true when the run ended with a result worth showing (won or lost).
local function playRun(): boolean
	resetRun()
	local run = GameService.Run
	for day = 1, Config.Run.Days do
		local night = Nights.Days[day]
		run.Day = day

		setState("Day", night.DayDuration)
		if not waitTimed(night.DayDuration, phaseAborted) and not enoughPlayers() then
			return false
		end
		if lostReason then
			break
		end
		skipRequested = false

		setState("Night", night.NightDuration)
		if not waitTimed(night.NightDuration, phaseAborted) and not enoughPlayers() then
			return false
		end
		if lostReason then
			break
		end
		skipRequested = false

		if day < Config.Run.Days then
			setState("Shop", Config.Run.ShopSeconds)
			if not waitTimed(Config.Run.ShopSeconds, phaseAborted) and not enoughPlayers() then
				return false
			end
			if lostReason then
				break
			end
			skipRequested = false
		end
	end

	local won = lostReason == nil
	run.Result = if won then "Won" else "Lost"
	run.Reason = lostReason
	recordStats(won, run.Day)
	setState("Results", Config.Run.ResultsSeconds)
	Net.fireAll("RunResult", {
		Won = won,
		Day = run.Day,
		Served = run.Served,
		Lost = run.Lost,
		Earned = run.Earned,
		Reason = lostReason,
	})
	waitTimed(Config.Run.ResultsSeconds, function()
		return not enoughPlayers()
	end)
	return true
end

function GameService.GetState(): string
	return state
end

function GameService.OnStateChanged(callback: (string, number) -> ())
	table.insert(callbacks, callback)
end

function GameService.Lose(reason: string?)
	if (state == "Day" or state == "Night") and lostReason == nil then
		lostReason = reason or "Lost"
	end
end

function GameService.SkipNight()
	if state == "Night" then
		skipRequested = true
	end
end

function GameService.Init() end

function GameService.Start()
	while true do
		resetRun()
		setState("Ready", 0)
		while not enoughPlayers() do
			task.wait(0.5)
		end
		setState("Ready", Config.Run.ReadySeconds)
		if waitTimed(Config.Run.ReadySeconds, function()
			return not enoughPlayers()
		end) then
			playRun()
		end
	end
end

return GameService
