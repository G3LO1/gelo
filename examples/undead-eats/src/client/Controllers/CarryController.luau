-- Drop key for the carried item. The server owns the slot; this only sends the intent.
-- Plan: SYS-03 (UI-04 will add the carried-item indicator)

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local CarryController = {}

function CarryController.Init() end

function CarryController.Start()
	local player = Players.LocalPlayer
	ContextActionService:BindAction("DropItem", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and player:GetAttribute("Carrying") then
			Net.fire("DropItem")
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.G, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle("DropItem", "Drop")
end

return CarryController
