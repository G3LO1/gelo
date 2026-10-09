-- expect: PRICE-HARDCODED, PRICE-HARDCODED, SEC-CLIENT-KICK
local player = game:GetService("Players").LocalPlayer
local gui = player.PlayerGui:WaitForChild("Shop")
gui.VipButton.Text = "VIP - 499 Robux"
gui.CoinsButton.Text = `R$ 99`
-- prices for in-game currency are fine:
gui.SwordButton.Text = "Sword - 250 Coins"
if player:GetAttribute("Speed") and player:GetAttribute("Speed") > 100 then
	player:Kick("cheater")
end
