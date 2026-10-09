-- expect: PERF-LOOP-NO-YIELD, PERF-LOOP-NO-YIELD, PERF-FRAME-ALLOC, PURCHASE-MULTI-RECEIPT
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

-- fine: yields
while true do
	local mode = if workspace:GetAttribute("Night") then "night" else "day"
	if mode == "night" then
		print("night")
	end
	task.wait(1)
end

-- freezes: the nested if/for/function blocks must not hide the missing yield
while true do
	for _, part in workspace:GetChildren() do
		if part:IsA("BasePart") then
			part.Color = Color3.new(1, 0, 0)
		end
	end
	local function helper()
		return 1
	end
	helper()
end

repeat
	local x = 1 + 1
until false

-- fine: breaks out
repeat
	local ok = math.random() > 0.5
	if ok then
		break
	end
until false

RunService.Heartbeat:Connect(function(dt)
	local fx = Instance.new("Part")
	fx.Parent = workspace
end)

MarketplaceService.ProcessReceipt = function(receipt)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end
