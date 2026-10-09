-- Helpers for controllers that bind to UI built in Studio (ui/ui-spec.json -> ui/BuildUi.luau).
-- Missing elements only warn, so a renamed label breaks one feature, not the whole client.
--
-- UiBind.screen("Hud")                    -> ScreenGui in PlayerGui, or nil after a timeout
-- UiBind.find(root, "TimerPanel/Fill")     -> descendant by slash path, or nil (warns)
-- UiBind.pop(guiObject)                   -> short scale-in feedback (adds a "PopScale" UIScale)
-- UiBind.setFill(bar, fraction)           -> sets a fill frame's X scale, keeps its Y size
-- UiBind.formatCash(12450)                 -> "$12,450"

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UiBind = {}

local POP_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

function UiBind.screen(name: string, timeout: number?): ScreenGui?
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild(name, timeout or 10)
	if not gui then
		warn(`[UiBind] PlayerGui.{name} not found: run ui/BuildUi.luau in Studio and save the place`)
	end
	return gui :: ScreenGui?
end

function UiBind.find(root: Instance?, path: string): any
	local current = root
	for part in string.gmatch(path, "[^/]+") do
		current = current and current:FindFirstChild(part)
	end
	if not current then
		warn(`[UiBind] {root and root:GetFullName() or "?"}/{path} not found`)
	end
	return current
end

function UiBind.pop(object: GuiObject?, from: number?)
	if not object then
		return
	end
	local scale = object:FindFirstChild("PopScale") :: UIScale?
	if not scale then
		local created = Instance.new("UIScale")
		created.Name = "PopScale"
		created.Parent = object
		scale = created
	end
	local popScale = scale :: UIScale
	popScale.Scale = from or 0.85
	TweenService:Create(popScale, POP_INFO, { Scale = 1 }):Play()
end

function UiBind.setFill(bar: GuiObject?, fraction: number)
	if not bar then
		return
	end
	local size = bar.Size
	bar.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, size.Y.Scale, size.Y.Offset)
end

function UiBind.formatCash(amount: number): string
	local digits = tostring(math.floor(amount))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return "$" .. grouped
end

return UiBind
