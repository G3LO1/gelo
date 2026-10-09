-- Small server helpers for checking a player's character.
--
-- PlayerUtil.getRoot(player)           -> HumanoidRootPart of a living character, or nil
-- PlayerUtil.isNear(player, target, d) -> true if the living character is within d studs of target

local PlayerUtil = {}

function PlayerUtil.getRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function PlayerUtil.isNear(player: Player, target: Instance, distance: number): boolean
	local root = PlayerUtil.getRoot(player)
	if not root then
		return false
	end
	local position = if target:IsA("BasePart")
		then target.Position
		elseif target:IsA("Model") then target:GetPivot().Position
		else nil
	if not position then
		return false
	end
	return (root.Position - position).Magnitude <= distance
end

return PlayerUtil
